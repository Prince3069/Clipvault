// android/app/src/main/java/com/yourapp/allsocialdownloader/services/MediaDetectionAccessibilityService.java

package com.yourapp.allsocialdownloader.services;

import android.accessibilityservice.AccessibilityService;
import android.accessibilityservice.AccessibilityServiceInfo;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.util.Log;
import android.view.accessibility.AccessibilityEvent;
import android.view.accessibility.AccessibilityNodeInfo;

import java.util.Arrays;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

import io.flutter.plugin.common.MethodChannel;

public class MediaDetectionAccessibilityService extends AccessibilityService {
    
    private static final String TAG = "MediaDetectionAccessibility";
    
    // Method channel for communication with Flutter
    private static MethodChannel methodChannel;
    
    // Supported social media apps
    private static final Set<String> SUPPORTED_APPS = new HashSet<>(Arrays.asList(
        "com.whatsapp",
        "com.whatsapp.w4b",
        "com.instagram.android", 
        "com.facebook.katana",
        "com.zhiliaoapp.musically",
        "com.twitter.android",
        "org.telegram.messenger",
        "com.snapchat.android"
    ));
    
    // Track current app and media state
    private String currentPackage = "";
    private boolean isMediaVisible = false;
    private long lastEventTime = 0;
    
    // Media detection keywords for different apps
    private static final Map<String, List<String>> MEDIA_KEYWORDS = new HashMap<String, List<String>>() {{
        put("com.whatsapp", Arrays.asList("status", "image", "video", "play", "pause"));
        put("com.instagram.android", Arrays.asList("reel", "story", "post", "video", "image", "play"));
        put("com.facebook.katana", Arrays.asList("video", "photo", "post", "story", "reel"));
        put("com.zhiliaoapp.musically", Arrays.asList("video", "play", "pause", "for you"));
        put("com.twitter.android", Arrays.asList("video", "image", "photo", "gif", "play"));
    }};
    
    public static void setMethodChannel(MethodChannel channel) {
        methodChannel = channel;
    }
    
    @Override
    public void onAccessibilityEvent(AccessibilityEvent event) {
        try {
            // Only process events from supported apps
            String packageName = event.getPackageName().toString();
            if (!SUPPORTED_APPS.contains(packageName)) {
                return;
            }
            
            // Avoid processing too many events
            long currentTime = System.currentTimeMillis();
            if (currentTime - lastEventTime < 500) { // 500ms throttle
                return;
            }
            lastEventTime = currentTime;
            
            // Update current package
            if (!packageName.equals(currentPackage)) {
                currentPackage = packageName;
                Log.d(TAG, "Switched to app: " + packageName);
                notifyAppChanged(packageName);
            }
            
            // Process different event types
            int eventType = event.getEventType();
            switch (eventType) {
                case AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED:
                case AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED:
                    handleContentChanged(event, packageName);
                    break;
                    
                case AccessibilityEvent.TYPE_VIEW_CLICKED:
                    handleViewClicked(event, packageName);
                    break;
                    
                case AccessibilityEvent.TYPE_VIEW_SCROLLED:
                    handleViewScrolled(event, packageName);
                    break;
            }
            
        } catch (Exception e) {
            Log.e(TAG, "Error processing accessibility event", e);
        }
    }
    
    private void handleContentChanged(AccessibilityEvent event, String packageName) {
        try {
            AccessibilityNodeInfo source = event.getSource();
            if (source == null) return;
            
            // Check for media-related content
            boolean mediaDetected = detectMediaInNode(source, packageName);
            
            if (mediaDetected && !isMediaVisible) {
                isMediaVisible = true;
                Log.d(TAG, "Media detected in " + packageName);
                notifyMediaDetected(packageName, true);
                
                // Try to get specific media information
                String mediaInfo = extractMediaInfo(source, packageName);
                if (mediaInfo != null) {
                    notifyMediaInfo(packageName, mediaInfo);
                }
            } else if (!mediaDetected && isMediaVisible) {
                isMediaVisible = false;
                Log.d(TAG, "Media no longer visible in " + packageName);
                notifyMediaDetected(packageName, false);
            }
            
        } catch (Exception e) {
            Log.e(TAG, "Error handling content changed", e);
        }
    }
    
    private void handleViewClicked(AccessibilityEvent event, String packageName) {
        try {
            AccessibilityNodeInfo source = event.getSource();
            if (source == null) return;
            
            // Check if user clicked on media content
            String clickedContent = getTextFromNode(source);
            if (isMediaRelatedClick(clickedContent, packageName)) {
                Log.d(TAG, "Media-related click detected: " + clickedContent);
                notifyMediaInteraction(packageName, "click", clickedContent);
            }
            
        } catch (Exception e) {
            Log.e(TAG, "Error handling view clicked", e);
        }
    }
    
    private void handleViewScrolled(AccessibilityEvent event, String packageName) {
        try {
            // Detect when user scrolls through media content (like Instagram reels, TikTok)
            if (packageName.equals("com.instagram.android") || 
                packageName.equals("com.zhiliaoapp.musically")) {
                
                Log.d(TAG, "Media scroll detected in " + packageName);
                notifyMediaInteraction(packageName, "scroll", "");
                
                // Check for new media after scroll
                AccessibilityNodeInfo source = event.getSource();
                if (source != null) {
                    detectMediaInNode(source, packageName);
                }
            }
            
        } catch (Exception e) {
            Log.e(TAG, "Error handling view scrolled", e);
        }
    }
    
    private boolean detectMediaInNode(AccessibilityNodeInfo node, String packageName) {
        if (node == null) return false;
        
        try {
            // Check current node for media indicators
            if (isMediaNode(node, packageName)) {
                return true;
            }
            
            // Recursively check child nodes
            int childCount = node.getChildCount();
            for (int i = 0; i < childCount; i++) {
                AccessibilityNodeInfo child = node.getChild(i);
                if (child != null) {
                    if (detectMediaInNode(child, packageName)) {
                        return true;
                    }
                    child.recycle();
                }
            }
            
        } catch (Exception e) {
            Log.e(TAG, "Error detecting media in node", e);
        }
        
        return false;
    }
    
    private boolean isMediaNode(AccessibilityNodeInfo node, String packageName) {
        try {
            // Check class name for media-related views
            String className = node.getClassName() != null ? node.getClassName().toString() : "";
            if (className.contains("VideoView") || 
                className.contains("ImageView") ||
                className.contains("MediaController") ||
                className.contains("PlayerView")) {
                return true;
            }
            
            // Check content description
            String contentDesc = node.getContentDescription() != null ? 
                node.getContentDescription().toString().toLowerCase() : "";
            
            // Check text content
            String text = node.getText() != null ? node.getText().toString().toLowerCase() : "";
            
            // Combine all text content
            String allContent = (contentDesc + " " + text).toLowerCase();
            
            // Check for media keywords specific to the app
            List<String> keywords = MEDIA_KEYWORDS.get(packageName);
            if (keywords != null) {
                for (String keyword : keywords) {
                    if (allContent.contains(keyword)) {
                        return true;
                    }
                }
            }
            
            // App-specific media detection
            return detectAppSpecificMedia(node, packageName, allContent);
            
        } catch (Exception e) {
            Log.e(TAG, "Error checking media node", e);
            return false;
        }
    }
    
    private boolean detectAppSpecificMedia(AccessibilityNodeInfo node, String packageName, String content) {
        switch (packageName) {
            case "com.whatsapp":
            case "com.whatsapp.w4b":
                return detectWhatsAppMedia(node, content);
                
            case "com.instagram.android":
                return detectInstagramMedia(node, content);
                
            case "com.facebook.katana":
                return detectFacebookMedia(node, content);
                
            case "com.zhiliaoapp.musically":
                return detectTikTokMedia(node, content);
                
            case "com.twitter.android":
                return detectTwitterMedia(node, content);
                
            default:
                return false;
        }
    }
    
    private boolean detectWhatsAppMedia(AccessibilityNodeInfo node, String content) {
        // WhatsApp status detection
        return content.contains("status") || 
               content.contains("view once") ||
               content.contains("tap to view") ||
               (content.contains("image") || content.contains("video")) && 
               content.contains("download");
    }
    
    private boolean detectInstagramMedia(AccessibilityNodeInfo node, String content) {
        // Instagram reels, stories, posts detection
        return content.contains("reel") ||
               content.contains("story") ||
               content.contains("double tap") ||
               content.contains("like") && (content.contains("video") || content.contains("photo")) ||
               content.contains("save") && content.contains("post");
    }
    
    private boolean detectFacebookMedia(AccessibilityNodeInfo node, String content) {
        // Facebook video/photo posts detection
        return content.contains("video") && (content.contains("play") || content.contains("pause")) ||
               content.contains("photo") && content.contains("view") ||
               content.contains("story") ||
               content.contains("reel");
    }
    
    private boolean detectTikTokMedia(AccessibilityNodeInfo node, String content) {
        // TikTok video detection
        return content.contains("for you") ||
               content.contains("following") ||
               content.contains("heart") ||
               content.contains("share") ||
               content.contains("comment");
    }
    
    private boolean detectTwitterMedia(AccessibilityNodeInfo node, String content) {
        // Twitter media detection
        return content.contains("gif") ||
               content.contains("video") && content.contains("tweet") ||
               content.contains("image") && content.contains("tweet") ||
               content.contains("media");
    }
    
    
    
    private String extractMediaInfo(AccessibilityNodeInfo node, String packageName) {
        try {
            // Try to extract specific media information
            StringBuilder mediaInfo = new StringBuilder();
            
            // Get video duration if available
            String duration = findDuration(node);
            if (duration != null) {
                mediaInfo.append("duration:").append(duration).append(";");
            }
            
            // Get media title/description
            String title = findMediaTitle(node, packageName);
            if (title != null) {
                mediaInfo.append("title:").append(title).append(";");
            }
            
            // Get author/creator info
            String author = findAuthor(node, packageName);
            if (author != null) {
                mediaInfo.append("author:").append(author).append(";");
            }
            
            return mediaInfo.length() > 0 ? mediaInfo.toString() : null;
            
        } catch (Exception e) {
            Log.e(TAG, "Error extracting media info", e);
            return null;
        }
    }
    
    private String findDuration(AccessibilityNodeInfo node) {
        // Look for duration pattern (mm:ss or hh:mm:ss)
        String text = getTextFromNode(node);
        if (text != null && text.matches(".*\\d{1,2}:\\d{2}.*")) {
            return text.replaceAll(".*?(\\d{1,2}:\\d{2}(?::\\d{2})?).*", "$1");
        }
        return null;
    }
    
    private String findMediaTitle(AccessibilityNodeInfo node, String packageName) {
        // App-specific title extraction logic
        switch (packageName) {
            case "com.instagram.android":
                return findInstagramTitle(node);
            case "com.zhiliaoapp.musically":
                return findTikTokTitle(node);
            default:
                return null;
        }
    }
    
    private String findInstagramTitle(AccessibilityNodeInfo node) {
        // Look for Instagram caption or description
        String text = getTextFromNode(node);
        if (text != null && text.length() > 10 && !text.matches(".*\\d{1,2}:\\d{2}.*")) {
            return text.substring(0, Math.min(100, text.length()));
        }
        return null;
    }
    
    private String findTikTokTitle(AccessibilityNodeInfo node) {
        // Look for TikTok video description
        String text = getTextFromNode(node);
        if (text != null && text.startsWith("#") || (text != null && text.length() > 10)) {
            return text.substring(0, Math.min(100, text.length()));
        }
        return null;
    }
    
    private String findAuthor(AccessibilityNodeInfo node, String packageName) {
        // Look for username or author information
        String text = getTextFromNode(node);
        if (text != null && text.startsWith("@")) {
            return text.split("\\s")[0]; // First word starting with @
        }
        return null;
    }
    
    private String getTextFromNode(AccessibilityNodeInfo node) {
        if (node == null) return null;
        
        StringBuilder text = new StringBuilder();
        
        // Get text content
        if (node.getText() != null) {
            text.append(node.getText().toString()).append(" ");
        }
        
        // Get content description
        if (node.getContentDescription() != null) {
            text.append(node.getContentDescription().toString()).append(" ");
        }
        
        // Recursively get text from children
        try {
            int childCount = node.getChildCount();
            for (int i = 0; i < childCount && i < 10; i++) { // Limit to avoid deep recursion
                AccessibilityNodeInfo child = node.getChild(i);
                if (child != null) {
                    String childText = getTextFromNode(child);
                    if (childText != null) {
                        text.append(childText).append(" ");
                    }
                    child.recycle();
                }
            }
        } catch (Exception e) {
            Log.e(TAG, "Error getting text from child nodes", e);
        }
        
        return text.length() > 0 ? text.toString().trim() : null;
    }
    
    private boolean isMediaRelatedClick(String clickedContent, String packageName) {
        if (clickedContent == null) return false;
        
        String content = clickedContent.toLowerCase();
        List<String> keywords = MEDIA_KEYWORDS.get(packageName);
        
        if (keywords != null) {
            for (String keyword : keywords) {
                if (content.contains(keyword)) {
                    return true;
                }
            }
        }
        
        return false;
    }
    
    // Notification methods to communicate with Flutter
    private void notifyAppChanged(String packageName) {
        if (methodChannel != null) {
            Map<String, Object> data = new HashMap<>();
            data.put("event", "app_changed");
            data.put("packageName", packageName);
            data.put("timestamp", System.currentTimeMillis());
            
            methodChannel.invokeMethod("onAccessibilityEvent", data);
        }
    }
    
    private void notifyMediaDetected(String packageName, boolean isVisible) {
        if (methodChannel != null) {
            Map<String, Object> data = new HashMap<>();
            data.put("event", "media_detected");
            data.put("packageName", packageName);
            data.put("isVisible", isVisible);
            data.put("timestamp", System.currentTimeMillis());
            
            methodChannel.invokeMethod("onMediaDetected", data);
        }
    }
    
    private void notifyMediaInfo(String packageName, String mediaInfo) {
        if (methodChannel != null) {
            Map<String, Object> data = new HashMap<>();
            data.put("event", "media_info");
            data.put("packageName", packageName);
            data.put("mediaInfo", mediaInfo);
            data.put("timestamp", System.currentTimeMillis());
            
            methodChannel.invokeMethod("onMediaInfo", data);
        }
    }
    
    private void notifyMediaInteraction(String packageName, String interactionType, String content) {
        if (methodChannel != null) {
            Map<String, Object> data = new HashMap<>();
            data.put("event", "media_interaction");
            data.put("packageName", packageName);
            data.put("interactionType", interactionType);
            data.put("content", content);
            data.put("timestamp", System.currentTimeMillis());
            
            methodChannel.invokeMethod("onMediaInteraction", data);
        }
    }
    
    @Override
    public void onInterrupt() {
        Log.d(TAG, "Accessibility service interrupted");
    }
    
    @Override
    protected void onServiceConnected() {
        Log.d(TAG, "Accessibility service connected");
        
        // Configure the service
        AccessibilityServiceInfo info = getServiceInfo();
        if (info != null) {
            info.eventTypes = AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED |
                            AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED |
                            AccessibilityEvent.TYPE_VIEW_CLICKED |
                            AccessibilityEvent.TYPE_VIEW_SCROLLED;
            
            info.feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC;
            info.flags = AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS |
                        AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS;
            info.notificationTimeout = 100;
            
            setServiceInfo(info);
        }
        
        // Notify Flutter that service is ready
        if (methodChannel != null) {
            Map<String, Object> data = new HashMap<>();
            data.put("event", "service_connected");
            data.put("timestamp", System.currentTimeMillis());
            
            methodChannel.invokeMethod("onServiceConnected", data);
        }
    }
    
    @Override
    public boolean onUnbind(Intent intent) {
        Log.d(TAG, "Accessibility service unbound");
        
        // Notify Flutter that service is disconnected
        if (methodChannel != null) {
            Map<String, Object> data = new HashMap<>();
            data.put("event", "service_disconnected");
            data.put("timestamp", System.currentTimeMillis());
            
            methodChannel.invokeMethod("onServiceDisconnected", data);
        }
        
        return super.onUnbind(intent);
    }
}