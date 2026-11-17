package com.nabdh.max;
import android.app.Activity;
import android.os.Bundle;
import android.os.Build;
import android.content.Intent;
import android.net.Uri;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceError;
import android.webkit.JavascriptInterface;
import android.graphics.Color;
public class MainActivity extends Activity {
 private static final String SITE="https://raw.githack.com/ammar100050000-netizen/ammar/main/nabdh-net/index.html";
 private static final String APK="https://github.com/ammar100050000-netizen/ammar/releases/latest/download/NabdhNet_MAX_ULTRA.apk";
 WebView web; boolean fallback=false;
 @Override public void onCreate(Bundle b){super.onCreate(b);getWindow().setStatusBarColor(Color.rgb(4,15,26));
   web=new WebView(this);setContentView(web);web.setBackgroundColor(Color.rgb(7,19,39));
   web.getSettings().setJavaScriptEnabled(true);web.getSettings().setDomStorageEnabled(true);
   web.addJavascriptInterface(new Bridge(),"NabdhAndroid");
   web.setWebViewClient(new WebViewClient(){
     @Override public void onReceivedError(WebView v,WebResourceRequest r,WebResourceError e){
       if(r.isForMainFrame()&&!fallback){fallback=true;v.loadUrl("file:///android_asset/index.html");}
     }
     @Override public boolean shouldOverrideUrlLoading(WebView v,WebResourceRequest r){
       Uri u=r.getUrl();String h=u.getHost();if("raw.githack.com".equals(h))return false;
       try{startActivity(new Intent(Intent.ACTION_VIEW,u));}catch(Exception ignored){}return true;
     }
   });web.loadUrl(SITE+"?t="+System.currentTimeMillis());
 }
 public class Bridge {
   @JavascriptInterface public void start(){runOnUiThread(()->{
     if(Build.VERSION.SDK_INT>=33&&checkSelfPermission("android.permission.POST_NOTIFICATIONS")!=getPackageManager().PERMISSION_GRANTED)requestPermissions(new String[]{"android.permission.POST_NOTIFICATIONS"},27);
     Intent i=new Intent(MainActivity.this,SpeedService.class);i.setAction("START");startForegroundService(i);
   });}
   @JavascriptInterface public void stop(){runOnUiThread(()->{Intent i=new Intent(MainActivity.this,SpeedService.class);i.setAction("STOP");startService(i);});}
   @JavascriptInterface public void openRelease(){runOnUiThread(()->{try{startActivity(new Intent(Intent.ACTION_VIEW,Uri.parse(APK)));}catch(Exception ignored){}});}
 }
 @Override public void onBackPressed(){if(web.canGoBack())web.goBack();else super.onBackPressed();}
}