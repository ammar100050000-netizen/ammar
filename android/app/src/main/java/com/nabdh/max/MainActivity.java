package com.nabdh.max;

import android.app.Activity;
import android.content.Intent;
import android.content.SharedPreferences;
import android.graphics.Color;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.webkit.JavascriptInterface;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceError;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.webkit.WebSettings;
import org.json.JSONObject;
import java.util.Locale;

public final class MainActivity extends Activity {
    private WebView web;
    private final Handler main = new Handler(Looper.getMainLooper());
    private boolean displayed = false;
    private long lastBytes = 0;
    private final Runnable updater = new Runnable() {
        @Override public void run() {
            try {
                if (web != null && displayed) {
                    SharedPreferences sp = getSharedPreferences("nabdh_speed_stats", MODE_PRIVATE);
                    boolean running = sp.getBoolean("is_running",false);
                    long total = sp.getLong("total_bytes",0L);
                    long wbytes = sp.getLong("window_bytes",0L);
                    long wms = sp.getLong("window_ms",1000L);
                    long elapsed = sp.getLong("elapsed_ms",0L);
                    int threads = sp.getInt("active_connections",0);
                    StringBuilder report = new StringBuilder();
                    report.append(wbytes).append('|').append(wms).append('|')
                          .append(total).append('|').append(threads).append('|')
                          .append(elapsed).append('|').append(running?"1":"0")
                          .append("|المحرك: تنزيل HTTPS متوازٍ");
                    for(int i=0;i<10;i++)report.append('|').append(sp.getLong("lane_"+i,0L));
                    web.evaluateJavascript("if(typeof window.nbUpdate==='function')window.nbUpdate("+
                      JSONObject.quote(report.toString())+");",null);
                }
            } catch (Exception ignored) { }
            main.postDelayed(this,1000L);
        }
    };

    private void begin(String mode) {
        if (Build.VERSION.SDK_INT >= 33
          && checkSelfPermission("android.permission.POST_NOTIFICATIONS")
                   != getPackageManager().PERMISSION_GRANTED)
            requestPermissions(new String[]{"android.permission.POST_NOTIFICATIONS"},27);
        Intent intent = new Intent(this, SpeedService.class);
        intent.setAction("START");
        intent.putExtra("mode",mode);
        if (Build.VERSION.SDK_INT >= 26) startForegroundService(intent);
        else startService(intent);
    }
    private void end() {
        Intent intent = new Intent(this, SpeedService.class);
        intent.setAction("STOP");
        startService(intent);
    }

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        getWindow().setStatusBarColor(Color.rgb(7,9,19));
        web = new WebView(this);
        web.setBackgroundColor(Color.rgb(7,9,19));
        setContentView(web);
        WebSettings settings = web.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setAllowFileAccess(true);
        // The signed app owns this bundled UI; it fetches design CSS from its trusted GitHub repo.
        settings.setAllowUniversalAccessFromFileURLs(true);
        web.addJavascriptInterface(new Bridge(),"NabdhAndroid");
        web.setWebViewClient(new WebViewClient(){
            private boolean handle(Uri uri) {
                if (uri == null || !"nabdh".equalsIgnoreCase(uri.getScheme())) return false;
                String action=uri.getHost();
                if ("start".equals(action))
                    begin("normal".equals(uri.getQueryParameter("mode"))?"normal":
                          "strong".equals(uri.getQueryParameter("mode"))?"strong":"ultra");
                else if ("tenstart".equals(action)) begin("ultra");
                else if ("stop".equals(action)) end();
                return true;
            }
            @Override public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                if (handle(request.getUrl())) return true;
                Uri uri=request.getUrl();
                if ("file".equals(uri.getScheme())) return false;
                if ("https".equals(uri.getScheme())) {
                    try {startActivity(new Intent(Intent.ACTION_VIEW,uri));}catch(Exception ignored){}
                }
                return true;
            }
            @Override public void onPageFinished(WebView view,String url) {
                displayed=true;
            }
            @Override public void onReceivedError(WebView view,WebResourceRequest request,WebResourceError error) {
                // Keep the bundled interface; do not replace it with a network-dependent page.
            }
        });
        web.loadUrl("file:///android_asset/index.html");
        main.post(updater);
    }
    public final class Bridge {
        @JavascriptInterface public void start(){runOnUiThread(()->begin("ultra"));}
        @JavascriptInterface public void start(String mode){runOnUiThread(()->begin(mode));}
        @JavascriptInterface public void stop(){runOnUiThread(()->end());}
    }
    @Override public void onBackPressed(){
        if(web!=null&&web.canGoBack())web.goBack();else super.onBackPressed();
    }
    @Override protected void onDestroy(){
        main.removeCallbacks(updater);
        if(web!=null)web.destroy();
        super.onDestroy();
    }
}