import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';


class AuthService {
  final Dio _dio = Dio(BaseOptions(baseUrl: "https://api.yourapp.com"));
  final storage = FlutterSecureStorage();

  AuthService()
      : _dio = Dio(BaseOptions(baseUrl: "https://api.yourapp.com")) {
    // **Add interceptors here**:
    _dio.interceptors.add(InterceptorsWrapper(
        onRequest:(options, handler) async {
          final token = await storage.read(key: "access");
          if (token != null) options.headers["Authorization"] = "Bearer $token";
          return handler.next(options);
        },
        onError:(err, handler) async {
          if (err.response?.statusCode == 401) {
            final didRefresh = await AuthService().tryRefresh();
            if (didRefresh) {
              // retry original request
              final opts = err.requestOptions;
              opts.headers["Authorization"] = "Bearer ${await storage.read(key: "access")}";
              final clone = await _dio.request(opts.path,
                  options: Options(
                    method: opts.method,
                    headers: opts.headers,
                  ),
                  data: opts.data);
              return handler.resolve(clone);
            }
          }
          return handler.next(err);
        }
    ));
  }
  Future<bool> signup(String email, String pw) async {
    await _dio.post("/auth/signup", data: {"email": email, "password": pw});
    return true;
  }

  Future<void> login(String email, String pw) async {
    final res = await _dio.post("/auth/token", data: {"email": email, "password": pw});
    await storage.write(key: "access", value: res.data["access_token"]);
    await storage.write(key: "refresh", value: res.data["refresh_token"]);
  }

  Future<String?> getAccessToken() async => await storage.read(key: "access");

  Future<void> login(String email, String pw) async {
    final res = await _dio.post("/auth/token", data: {"email": email, "password": pw});
    await storage.write(key: "access", value: res.data["access_token"]);
    await storage.write(key: "refresh", value: res.data["refresh_token"]);
  }



  Future<bool> tryRefresh() async {
    final refresh = await storage.read(key: "refresh");
    if (refresh == null) return false;
    try {
      final res = await _dio.post("/auth/refresh", data: refresh);
      await storage.write(key: "access", value: res.data["access_token"]);
      return true;
    } catch (_) {
      return false;
    }
  }
}


