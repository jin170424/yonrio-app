import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';

/// 現在のセッションからIDトークンを取得する
/// 未ログイン時やエラー時は null を返す

class GetIdtokenService {

  Future<String?> getIdtoken() async {
    try {
      // セッションを取得
      final session = await Amplify.Auth.fetchAuthSession();

      // ログインしているか確認
      if (!session.isSignedIn) {
        print('未ログイン状態です');
        return null;
      }

      // Cognitoのセッションとしてキャストし、トークンを取り出す
      final cognitoSession = session as CognitoAuthSession;
      
      // idToken, accessToken, refreshToken などが含まれています
      // ここでは raw (文字列) の IDトークン を取得
      // print(cognitoSession.userPoolTokensResult.value.idToken.raw);
      return cognitoSession.userPoolTokensResult.value.idToken.raw;

    } catch (e) {
      print('トークン取得エラー: $e');
      return null;
    }
  }
}