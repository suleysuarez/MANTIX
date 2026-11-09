import 'file_picker_service.dart';
import 'image_picker_service.dart';
import 'share_service.dart';
import 'temp_file_service.dart';

/// Lo que la app usa del teléfono (selectores, compartir y archivos temporales), junto, para
/// pasarlo una sola vez a `MantixApp`. Las pruebas lo sustituyen por versiones simuladas.
class DeviceServices {
  DeviceServices({FilePickerService? filePicker, ImagePickerService? imagePicker, ShareService? share, TempFileService? tempFiles})
      : filePicker = filePicker ?? const SystemFilePickerService(),
        imagePicker = imagePicker ?? SystemImagePickerService(),
        share = share ?? const SystemShareService(),
        tempFiles = tempFiles ?? const SystemTempFileService();

  final FilePickerService filePicker;
  final ImagePickerService imagePicker;
  final ShareService share;
  final TempFileService tempFiles;
}
