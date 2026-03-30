import 'package:device_info_plus/src/device_info_plus_web.dart';
import 'package:flutter_web_auth_2/src/web.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:package_info_plus/src/package_info_plus_web.dart';
import 'package:record_web/record_web.dart';
import 'package:url_launcher_web/url_launcher_web.dart';

void registerWebPlugins() {
  final Registrar registrar = webPluginRegistrar;
  DeviceInfoPlusWebPlugin.registerWith(registrar);
  FlutterWebAuth2WebPlugin.registerWith(registrar);
  PackageInfoPlusWebPlugin.registerWith(registrar);
  RecordPluginWeb.registerWith(registrar);
  UrlLauncherPlugin.registerWith(registrar);
  registrar.registerMessageHandler();
}
