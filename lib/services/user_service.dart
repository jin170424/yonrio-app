import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UserService {
  // シングルトン どこから呼んでも同じインスタンス
  static final UserService _instance = UserService._internal();
  factory UserService() => _instance;
  UserService._internal();

  Future<String?> getPreferredUsername() async {
    try {
      final attributes = await Amplify.Auth.fetchUserAttributes();
      String? onlineName;
      for (final element in attributes) {
        // CognitoUserAttributeKey.preferredUsername を使用して比較
        if (element.userAttributeKey == CognitoUserAttributeKey.preferredUsername) {
          onlineName = element.value;
          break;
        }
      }
      
      // 名前あったら、オフライン時のためにキャッシュしておく
      if (onlineName != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('cached_preferred_name', onlineName);
        return onlineName;
      }

      return "unknownuser"; // オンラインでもなかった場合
      
    } catch (e) {
      // エラーまたはオフラインならキャッシュを見る
      safePrint('オンライン取得失敗。キャッシュを使用します: $e');

      final prefs = await SharedPreferences.getInstance();
      final cachedName = prefs.getString('cached_preferred_name');

      return cachedName; // キャッシュの名前を返す、なければnull
      
    }
  }

  Future<void> syncUserAttributes() async {
    try {
      final attributes = await Amplify.Auth.fetchUserAttributes();
      final nameAttr = attributes.firstWhere(
        (element) => element.userAttributeKey == AuthUserAttributeKey.preferredUsername,
        orElse: () => const AuthUserAttribute(
          userAttributeKey: AuthUserAttributeKey.preferredUsername, 
          value: ''
        ),
      );
      
      if (nameAttr.value.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('cached_preferred_name', nameAttr.value);
      }
    } catch (e) {
      // オフラインなどで失敗しても、ここではエラーを出さずに無視する
      print('Sync failed, offline or error: $e');
    }
  }
  Future<String?> getCurrentUserSub() async {
    try {
      final attributes = await Amplify.Auth.fetchUserAttributes();
      // 'sub' 属性を探して値を返す
      final subAttribute = attributes.firstWhere(
        (element) => element.userAttributeKey.key == 'sub',
      );
      return subAttribute.value;
    } catch (e) {
      print('Error fetching user sub: $e');
      return null;
    }
  }
}