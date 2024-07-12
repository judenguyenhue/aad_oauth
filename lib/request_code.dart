import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'model/config.dart';
import 'request/authorization_request.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

class RequestCode {
  final Config _config;
  final AuthorizationRequest _authorizationRequest;
  final String _redirectUriHost;
  late NavigationDelegate _navigationDelegate;
  String? _code;
  late final WebViewController controller;
  final cookieManager = WebViewCookieManager();

  RequestCode(Config config)
      : _config = config,
        _authorizationRequest = AuthorizationRequest(config),
        _redirectUriHost = Uri.parse(config.redirectUri).host {
    _navigationDelegate = NavigationDelegate(
      onNavigationRequest: _onNavigationRequest,
      onWebResourceError: (error) {
        String url = error.url ?? "";
        if (url.isEmpty || !url.contains('http')) {
          print('===onWebResource error: empty or non-http url load');
        } else {
          print('===onWebResource error: ${error.description}, url: $url');
          showErrorMessage(
            _config.navigatorKey.currentState?.overlay?.context,
            'Load web source failed: ${error.description}, url: $url',
          );
        }
      },
      onUrlChange: (url) {
        print('===onUrlChange: ${url.url ?? ""}');
      },
      onPageFinished: (url) {
        print('===onPageFinished: $url');
      },
    );
  }

  Future<String?> requestCode() async {
    _code = null;

    final urlParams = _constructUrlParams();
    final launchUri = Uri.parse('${_authorizationRequest.url}?$urlParams');
    controller = WebViewController();
    await controller.setNavigationDelegate(_navigationDelegate);
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    final WebViewCookieManager cookieManager = WebViewCookieManager();
    if (WebViewPlatform.instance is AndroidWebViewPlatform) {
      final AndroidWebViewCookieManager androidManager =
          cookieManager.platform as AndroidWebViewCookieManager;
      androidManager.setAcceptThirdPartyCookies(
          controller.platform as AndroidWebViewController, true);
      print('Web controller accepted 3rd party cookies');
    }
    await controller.setBackgroundColor(Colors.transparent);
    await controller.setUserAgent(_config.userAgent);
    await controller.loadRequest(launchUri);

    final webView = WebViewWidget(controller: controller);

    if (_config.navigatorKey.currentState == null) {
      String errMessage =
          'Could not push new route using provided navigatorKey, Because '
          'NavigatorState returned from provided navigatorKey is null. Please Make sure '
          'provided navigatorKey is passed to WidgetApp. This can also happen if at the time of this method call '
          'WidgetApp is not part of the flutter widget tree';

      showErrorMessage(
        _config.navigatorKey.currentState?.overlay?.context,
        'Load web source failed: $errMessage, url: ${_authorizationRequest.url}, params: $urlParams',
      );
      throw Exception(errMessage);
    }

    await _config.navigatorKey.currentState!.push(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: _config.appBar,
          body: WillPopScope(
            onWillPop: () async {
              if (await controller.canGoBack()) {
                await controller.goBack();
                return false;
              }
              return true;
            },
            child: SafeArea(
              child: Stack(
                children: [_config.loader, webView],
              ),
            ),
          ),
        ),
      ),
    );
    return _code;
  }

  Future<NavigationDecision> _onNavigationRequest(
      NavigationRequest request) async {
    try {
      var uri = Uri.parse(request.url);

      if (uri.queryParameters['error'] != null) {
        _config.navigatorKey.currentState!.pop();
      }

      var checkHost = uri.host == _redirectUriHost;

      if (uri.queryParameters['code'] != null && checkHost) {
        _code = uri.queryParameters['code'];
        _config.navigatorKey.currentState!.pop();
      }
    } catch (e) {
      print(
          '===onNavigationRequest error: $e, navigate state: ${_config.navigatorKey.currentState?.overlay?.context}');
      showErrorMessage(
        _config.navigatorKey.currentState?.overlay?.context,
        'Web navigation error: ${e.toString()}, url: ${request.url}',
      );
    }
    return NavigationDecision.navigate;
  }

  Future<void> clearCookies() async {
    await WebViewCookieManager().clearCookies();
  }

  String _constructUrlParams() => _mapToQueryParams(
      _authorizationRequest.parameters, _config.customParameters);

  String _mapToQueryParams(
      Map<String, String> params, Map<String, String> customParams) {
    final queryParams = <String>[];

    params.forEach((String key, String value) =>
        queryParams.add('$key=${Uri.encodeQueryComponent(value)}'));

    customParams.forEach((String key, String value) =>
        queryParams.add('$key=${Uri.encodeQueryComponent(value)}'));
    return queryParams.join('&');
  }

  void showErrorMessage(BuildContext? context, String text) {
    if (context == null) {
      return;
    }
    var alert = AlertDialog(
        title: Text('Error'),
        content: Text(text),
        actions: <Widget>[
          TextButton(
              child: const Text('OK'),
              onPressed: () {
                Navigator.pop(context);
              })
        ]);
    showDialog(
      context: context,
      builder: (BuildContext context) => alert,
    );
  }
}
