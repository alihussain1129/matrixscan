import '../interpret/interpreter.dart';
import '../interpret/scan_field.dart';
import 'verification.dart';

/// Offline checks of what the interpreters already established. It says
/// whether the structure is valid, never whether the item exists.
class StructuralSource implements VerificationSource {
  static const sourceInfo = SourceInfo(
    id: 'local-structure',
    name: 'Local format checks',
    kind: SourceKind.local,
  );

  @override
  SourceInfo get info => sourceInfo;

  @override
  bool appliesTo(Interpretation interpretation) => true;

  @override
  Future<SourceResult> check(Interpretation interpretation) async {
    final claims = <Claim>[];
    for (final f in interpretation.allFields) {
      if (f.sensitive || f.id == 'errors') continue;
      if (f.validation == FieldValidation.valid) {
        claims.add(
          Claim(
            aspect: f.label,
            status: VerificationStatus.validFormat,
            detail:
                'The structure is valid. This says nothing about whether the '
                'item exists or is genuine.',
          ),
        );
      } else if (f.validation == FieldValidation.invalid) {
        claims.add(
          Claim(
            aspect: f.label,
            status: VerificationStatus.invalidFormat,
            detail: f.warning ?? 'The value does not follow its format.',
          ),
        );
      }
      if (f.id == 'expiryStatus' && f.value == 'Expired') {
        claims.add(
          const Claim(
            aspect: 'Expiry date in barcode',
            status: VerificationStatus.expired,
            detail: 'Calculated on this device from the date in the barcode.',
          ),
        );
      }
    }
    return SourceResult(
      info: info,
      checkedAt: DateTime.now(),
      claims: claims,
    );
  }
}