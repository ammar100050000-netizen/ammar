package com.nabdh.max;
import android.app.*;import android.content.*;import android.os.*;import java.io.*;import java.net.*;
public class SpeedService extends Service {
 private volatile boolean running=false;private Thread worker;private long total;
 private static final String CHANNEL="speed";
 @Override public void onCreate(){super.onCreate();NotificationChannel ch=new NotificationChannel(CHANNEL,"نبض نت: سرعة مباشرة",NotificationManager.IMPORTANCE_LOW);getSystemService(NotificationManager.class).createNotificationChannel(ch);}
 @Override public int onStartCommand(Intent i,int flags,int id){
   if(i!=null&&"STOP".equals(i.getAction())){running=false;if(worker!=null)worker.interrupt();stopForeground(STOP_FOREGROUND_REMOVE);stopSelf();return START_NOT_STICKY;}
   if(running)return START_NOT_STICKY;
   running=true;total=0;startForeground(7,notification("بدء القياس..."));
   worker=new Thread(this::measure,"nabdh-speed");worker.start();return START_NOT_STICKY;
 }
 private Notification notification(String msg){
   Intent stop=new Intent(this,SpeedService.class);stop.setAction("STOP");
   PendingIntent pi=PendingIntent.getService(this,1,stop,PendingIntent.FLAG_IMMUTABLE|PendingIntent.FLAG_UPDATE_CURRENT);
   return new Notification.Builder(this,CHANNEL).setSmallIcon(android.R.drawable.stat_sys_download)
     .setContentTitle("نبض نت • قياس مستمر").setContentText(msg).setOngoing(true)
     .addAction(new Notification.Action.Builder(android.R.drawable.ic_media_pause,"إيقاف",pi).build()).build();
 }
 private void measure(){int fails=0;long start=SystemClock.elapsedRealtime(),window=0;
   while(running&&!Thread.currentThread().isInterrupted()){
     HttpURLConnection c=null;
     try{
       URL url=new URL("https://speed.cloudflare.com/__down?bytes=5000000&nonce="+System.nanoTime());
       c=(HttpURLConnection)url.openConnection();c.setConnectTimeout(7000);c.setReadTimeout(7000);c.setUseCaches(false);
       try(InputStream in=c.getInputStream()){
         byte[] b=new byte[65536];int n;
         while(running&&(n=in.read(b))!=-1){total+=n;window+=n;long now=SystemClock.elapsedRealtime();
           if(now-start>=1000){double mbps=window*8.0/(now-start)/1000.0;
             String msg=String.format(java.util.Locale.US,"%.1f Mbps • %.1f MB",mbps,total/1000000.0);
             getSystemService(NotificationManager.class).notify(7,notification(msg));window=0;start=now;}
         }
       }
       fails=0;
     }catch(Exception ex){
       fails++;getSystemService(NotificationManager.class).notify(7,notification("إعادة الاتصال..."));
       try{Thread.sleep(Math.min(30000,1000L*(1<<Math.min(fails,5))));}catch(InterruptedException e){Thread.currentThread().interrupt();}
     }finally{if(c!=null)c.disconnect();}
   }
   running=false;stopForeground(STOP_FOREGROUND_REMOVE);stopSelf();
 }
 @Override public void onDestroy(){running=false;if(worker!=null)worker.interrupt();super.onDestroy();}
 @Override public IBinder onBind(Intent i){return null;}
}