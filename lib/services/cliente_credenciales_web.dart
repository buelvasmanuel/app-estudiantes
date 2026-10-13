import 'package:http/browser_client.dart';
import 'package:http/http.dart' as http;

/// En la web: `fetch` con `credentials: "include"`.
http.Client? crear() => BrowserClient()..withCredentials = true;
