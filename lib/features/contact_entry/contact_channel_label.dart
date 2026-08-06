import '../../l10n/app_strings.dart';
import '../contact_journal/contact_models.dart';

/// Returns the localized label for a stable contact channel value.
String contactChannelLabel(AppStrings text, ContactChannel channel) {
  return switch (channel) {
    ContactChannel.faceToFace => text.t('channel.faceToFace'),
    ContactChannel.voiceCall => text.t('channel.voiceCall'),
    ContactChannel.videoCall => text.t('channel.videoCall'),
    ContactChannel.instantText => text.t('channel.instantText'),
    ContactChannel.asynchronousMessage => text.t('channel.asynchronousMessage'),
    ContactChannel.mixed => text.t('channel.mixed'),
    ContactChannel.otherDirect => text.t('channel.otherDirect'),
  };
}
