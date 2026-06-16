import 'package:flutter_test/flutter_test.dart';
import 'package:sgs_sha/core/models/skill_dto.dart';
import 'package:sgs_sha/features/reference/services/resolver_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ResolverService references', () {
    test(
      'general skill descriptions resolve cards, skills, and tokens',
      () async {
        final refs = await ResolverService().resolveGeneralSkills(const [
          SkillDTO(
            id: 'test_skill',
            skillType: SkillType.active,
            nameCn: 'test',
            nameEn: 'Test Skill',
            descriptionCn:
                '\u4f60\u53ef\u4ee5\u5c06\u4e00\u5f20\u300c\u7530\u300d'
                '\u5f53\u3010\u987a\u624b\u7275\u7f8a\u3011\u4f7f\u7528'
                '\uff0c\u7136\u540e\u83b7\u5f97\u3016\u6025\u88ad\u3017\u3002',
            descriptionEn:
                'You may use a \u300cField\u300d token as [Steal], '
                'then gain \u3016Swift Strike\u3017.',
          ),
        ], isChinese: false);

        expect(refs.map((ref) => ref.type.name), contains('libraryCard'));
        expect(refs.map((ref) => ref.type.name), contains('skill'));
        expect(refs.map((ref) => ref.type.name), contains('token'));
        expect(
          refs.map((ref) => ref.nameEn),
          containsAll(['Steal', 'Swift Strike', 'Field']),
        );
      },
    );

    test('library effect descriptions use the same reference logic', () async {
      final refs = await ResolverService().resolveLibraryEffects(const [
        'Use [Kill] with \u3016Saint of War\u3017 and place it as a '
            '\u300cValor\u300d token.',
        'Use [Kill] again to confirm duplicates are removed.',
      ], isChinese: false);

      expect(refs.where((ref) => ref.nameEn == 'Kill'), hasLength(1));
      expect(
        refs.map((ref) => ref.type.name),
        containsAll(['libraryCard', 'skill', 'token']),
      );
      expect(
        refs.map((ref) => ref.nameEn),
        containsAll(['Kill', 'Saint of War', 'Valor']),
      );
    });

    test(
      'Chinese token references resolve and canResolve after cache warmup',
      () async {
        await ResolverService().resolve('\u3010\u6740\u3011', isChinese: true);

        expect(
          ResolverService().canResolve('\u300c\u7530\u300d', isChinese: true),
          isTrue,
        );

        final refs = await ResolverService().resolve(
          '\u4f60\u53ef\u4ee5\u5c06\u4e00\u5f20\u300c\u7530\u300d'
          '\u5f53\u3010\u987a\u624b\u7275\u7f8a\u3011\u4f7f\u7528\u3002',
          isChinese: true,
        );

        expect(refs.map((ref) => ref.type.name), contains('token'));
        expect(refs.map((ref) => ref.nameCn), contains('\u7530'));
      },
    );
  });
}
