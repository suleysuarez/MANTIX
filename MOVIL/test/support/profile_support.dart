import 'package:mantix/models/equipment/attachment_models.dart';
import 'package:mantix/services/image_picker_service.dart';

/// `GET /profile` como lo envía el servidor.
Map<String, Object?> profileJson({
  String name = 'Ana Pérez',
  String? phone = '+57 300 123 4567',
  bool hasAvatar = false,
  int? avatarVersion,
  String? lastLogin = '2026-11-12T15:00:00Z',
}) =>
    {
      'id': 1,
      'email': 'ana@mantix.test',
      'full_name': name,
      'phone': phone,
      'employee_code': null,
      'roles': [
        {'id': 2, 'code': 'TECHNICIAN', 'name': 'Técnico', 'description': null, 'is_active': true},
      ],
      'has_avatar': hasAvatar,
      'avatar_version': hasAvatar ? (avatarVersion ?? 1) : null,
      'last_login_at': lastLogin,
      'created_at': '2026-10-01T12:00:00Z',
    };

/// Una fila de `GET /profile/history`.
Map<String, Object?> historyJson({int id = 1, String action = 'auth.login', String kind = 'session', String? actor, String at = '2026-11-12T15:00:00Z'}) => {
      'id': id,
      'action': action,
      'kind': kind,
      'entity_type': 'user',
      'entity_id': 1,
      'actor_name': actor,
      'ip_address': null,
      'created_at': at,
    };

/// Selector de fotos de mentira: devuelve [next] (o `null`, como si se cancelara).
class FakeImagePicker implements ImagePickerService {
  AttachmentFile? next;
  int camera = 0;
  int gallery = 0;

  @override
  Future<AttachmentFile?> takePhoto() async {
    camera++;
    return next;
  }

  @override
  Future<AttachmentFile?> pickFromGallery() async {
    gallery++;
    return next;
  }

  @override
  Future<AttachmentFile?> recoverLostPhoto() async => null;
}
