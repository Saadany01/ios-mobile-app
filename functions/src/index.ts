import * as admin from "firebase-admin";
import * as functions from "firebase-functions";

admin.initializeApp();

// Self-hosted coturn — secret never leaves the server.
const TURN_HOST = "41.34.73.190";
const TURN_SECRET = "f6233482ae1ab37f12de7b840833fc37560b86e74522295a71318dd3b14dda11";
const TURN_TTL = 3600; // 1 hour

const db = admin.firestore();
const messaging = admin.messaging();

interface ActiveCallData {
  callerId: string;
  callerName: string;
  callerPhotoUrl?: string;
  calleeId: string;
  calleeName: string;
  calleePhotoUrl?: string;
  status: string;
  mediaType: string;
  createdAt: admin.firestore.Timestamp;
}

interface UserData {
  fcmToken?: string;
}

/**
 * Triggered when a new active_calls document is created.
 * Sends an FCM push notification to the callee so they can
 * receive the incoming call even if the app is backgrounded or killed.
 */
export const onCallCreated = functions.firestore
  .document("active_calls/{callId}")
  .onCreate(async (snapshot, context) => {
    const callData = snapshot.data() as ActiveCallData;

    // Only send push for ringing calls
    if (callData.status !== "ringing") {
      return;
    }

    const callId = context.params.callId;

    // Fetch callee's FCM token
    const userDoc = await db
      .collection("users")
      .doc(callData.calleeId)
      .get();

    if (!userDoc.exists) {
      functions.logger.warn("Callee user not found", { calleeId: callData.calleeId });
      return;
    }

    const userData = userDoc.data() as UserData;

    if (!userData.fcmToken) {
      functions.logger.warn("Callee has no FCM token", { calleeId: callData.calleeId });
      return;
    }

    // Send high-priority data message for incoming call
    try {
      await messaging.send({
        token: userData.fcmToken,
        data: {
          type: "incoming_call",
          callId,
          callerId: callData.callerId,
          callerName: callData.callerName,
          callerPhotoUrl: callData.callerPhotoUrl ?? "",
          mediaType: callData.mediaType,
        },
        android: {
          priority: "high",
          ttl: 30_000, // 30 seconds — simulates ringing duration
          notification: {
            channelId: "incoming_calls",
            title: `Incoming ${callData.mediaType} call`,
            body: `${callData.callerName} is calling...`,
            clickAction: "FLUTTER_NOTIFICATION_CLICK",
          },
        },
        apns: {
          headers: {
            "apns-priority": "10",
            "apns-push-type": "alert",
          },
          payload: {
            aps: {
              sound: "incoming_call.caf",
              alert: {
                title: `Incoming ${callData.mediaType} call`,
                body: `${callData.callerName} is calling...`,
              },
            },
          },
        },
      });

      functions.logger.info("Call push notification sent", {
        callId,
        calleeId: callData.calleeId,
      });
    } catch (err) {
      functions.logger.error("Failed to send call push notification", err);
    }
  });

/**
 * Triggered when an active call document's status changes to a terminal state
 * (declined, canceled, ended). Sends a push notification to cancel/clear
 * the incoming call UI on the receiver's device.
 */
export const onCallStatusChanged = functions.firestore
  .document("active_calls/{callId}")
  .onUpdate(async (change, context) => {
    const before = change.before.data() as ActiveCallData;
    const after = change.after.data() as ActiveCallData;

    // Only act if status changed from "ringing" to a terminal state
    const terminalStatuses = new Set(["declined", "canceled"]);
    if (before.status !== "ringing" || !terminalStatuses.has(after.status)) {
      return;
    }

    // Determine which user to notify (the one who didn't trigger the change)
    const notifyUserId =
      after.endedBy === after.callerId ? after.calleeId : after.callerId;

    const userDoc = await db.collection("users").doc(notifyUserId).get();
    if (!userDoc.exists) return;

    const userData = userDoc.data() as UserData;
    if (!userData.fcmToken) return;

    try {
      await messaging.send({
        token: userData.fcmToken,
        data: {
          type: "call_cancelled",
          callId: context.params.callId,
        },
        android: { priority: "high", ttl: 5_000 },
        apns: {
          headers: { "apns-priority": "10" },
          payload: { aps: { contentAvailable: true } },
        },
      });
    } catch (err) {
      functions.logger.error("Failed to send call cancel notification", err);
    }
  });

/**
 * Triggered when a new message is created in a direct chat.
 * Sends an FCM push notification to the recipient so they get
 * notified even when the app is backgrounded or killed.
 */
export const onMessageSent = functions.firestore
  .document("direct_chats/{chatId}/messages/{messageId}")
  .onCreate(async (snapshot, context) => {
    const messageData = snapshot.data();
    if (!messageData) return;

    const chatId = context.params.chatId as string;
    const senderId = (messageData.senderId ?? "") as string;
    const senderName = (messageData.senderDisplayName ?? "Someone") as string;
    const text = (messageData.text ?? "") as string;

    if (!senderId) return;

    // Resolve the other participant via the friendship document (same id as chatId)
    const friendshipDoc = await db.collection("friendships").doc(chatId).get();
    if (!friendshipDoc.exists) return;

    const fd = friendshipDoc.data()!;
    const userAId = (fd.userAId ?? "") as string;
    const userBId = (fd.userBId ?? "") as string;
    if (!userAId || !userBId) return;

    const recipientId = senderId === userAId ? userBId : userAId;
    if (!recipientId || recipientId === senderId) return;

    const recipientDoc = await db.collection("users").doc(recipientId).get();
    if (!recipientDoc.exists) return;

    const recipientData = recipientDoc.data() as UserData;
    if (!recipientData.fcmToken) return;

    const preview = text.length > 80 ? text.substring(0, 77) + "…" : text;

    try {
      await messaging.send({
        token: recipientData.fcmToken,
        notification: {
          title: senderName,
          body: preview || "Sent you a message.",
        },
        data: {
          type: "direct_message",
          chatId,
          senderId,
          senderName,
        },
        android: {
          priority: "high",
          notification: {
            channelId: "direct_messages",
            clickAction: "FLUTTER_NOTIFICATION_CLICK",
          },
        },
        apns: {
          headers: { "apns-priority": "10" },
          payload: { aps: { sound: "default" } },
        },
      });
      functions.logger.info("Message notification sent", { chatId, recipientId });
    } catch (err) {
      functions.logger.error("Failed to send message notification", err);
    }
  });

/**
 * Callable function that returns time-limited TURN credentials for our
 * self-hosted coturn server. Uses HMAC-SHA1 shared secret — no third party.
 */
export const getTurnCredentials = functions.https.onCall(async (_data: any, context: any) => {
  if (!context?.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "You must be logged in to make calls."
    );
  }

  const crypto = await import("crypto");
  const expiry = Math.floor(Date.now() / 1000) + TURN_TTL;
  const username = `${expiry}:${context.auth.uid}`;
  const credential = crypto
    .createHmac("sha1", TURN_SECRET)
    .update(username)
    .digest("base64");

  return {
    iceServers: [
      { urls: "stun:stun.l.google.com:19302" },
      {
        urls: [
          `turn:${TURN_HOST}:3478?transport=udp`,
          `turn:${TURN_HOST}:3478?transport=tcp`,
        ],
        username,
        credential,
      },
    ],
  };
});
