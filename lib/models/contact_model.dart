class Contact {
  final String id;
  final String name;
  final String? linkedUserId;
  final String? phone;
  final String? email;
  final String? avatarUrl;
  final bool isFavorite;
  final bool isOnline;

  Contact({
    required this.id,
    required this.name,
    this.linkedUserId,
    this.phone,
    this.email,
    this.avatarUrl,
    this.isFavorite = false,
    this.isOnline = false,
  });

  factory Contact.fromFirestore(Map<String, dynamic> data, String id) {
    return Contact(
      id: id,
      name: data['name'] ?? 'Unknown',
      linkedUserId: data['linkedUserId'],
      phone: data['phone'],
      email: data['email'],
      avatarUrl: data['avatarUrl'],
      isFavorite: data['isFavorite'] ?? false,
      isOnline: data['isOnline'] ?? false,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'linkedUserId': linkedUserId,
      'phone': phone,
      'email': email,
      'avatarUrl': avatarUrl,
      'isFavorite': isFavorite,
      'isOnline': isOnline,
    };
  }
}
