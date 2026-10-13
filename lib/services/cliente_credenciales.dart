import 'package:http/http.dart' as http;

import 'cliente_credenciales_io.dart'
    if (dart.library.js_interop) 'cliente_credenciales_web.dart'
    as plataforma;

/// Un cliente que envía las cookies del navegador (`withCredentials`), para
/// el refresh en cookie de la web (CONTRATO_AUTH §6.3). `null` fuera de la
/// web: allí no hay cookies de navegador.
http.Client? clienteConCredenciales() => plataforma.crear();
