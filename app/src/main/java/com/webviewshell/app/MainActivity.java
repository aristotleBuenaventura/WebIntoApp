package com.webviewshell.app;

import android.animation.Animator;
import android.animation.AnimatorListenerAdapter;
import android.animation.ObjectAnimator;
import android.annotation.SuppressLint;
import android.content.Intent;
import android.graphics.Bitmap;
import android.graphics.Color;
import android.net.Uri;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.View;
import android.view.animation.DecelerateInterpolator;
import android.view.animation.OvershootInterpolator;
import android.webkit.CookieManager;
import android.webkit.DownloadListener;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.ProgressBar;

import androidx.activity.OnBackPressedCallback;
import androidx.appcompat.app.AppCompatActivity;
import androidx.core.graphics.Insets;
import androidx.core.view.ViewCompat;
import androidx.core.view.WindowCompat;
import androidx.core.view.WindowInsetsCompat;
import androidx.core.view.WindowInsetsControllerCompat;

public class MainActivity extends AppCompatActivity {

    private static final long MIN_SPLASH_MS = 1600L;

    private WebView webView;
    private ProgressBar progressBar;
    private FrameLayout splashContainer;
    private ImageView splashLogo;

    private final Handler handler = new Handler(Looper.getMainLooper());
    private boolean pageFinished;
    private boolean minSplashElapsed;
    private boolean splashHidden;

    @SuppressLint("SetJavaScriptEnabled")
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        WindowCompat.setDecorFitsSystemWindows(getWindow(), false);
        setContentView(R.layout.activity_main);

        View root = findViewById(R.id.rootContainer);
        View content = findViewById(R.id.contentContainer);
        splashContainer = findViewById(R.id.splashContainer);
        splashLogo = findViewById(R.id.splashLogo);
        webView = findViewById(R.id.webView);
        progressBar = findViewById(R.id.progressBar);

        applySystemBarInsets(root, content);
        styleSystemBars();
        playSplashIntro();

        WebSettings settings = webView.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setDatabaseEnabled(true);
        settings.setLoadWithOverviewMode(true);
        settings.setUseWideViewPort(true);
        settings.setSupportZoom(true);
        settings.setBuiltInZoomControls(true);
        settings.setDisplayZoomControls(false);
        settings.setCacheMode(WebSettings.LOAD_DEFAULT);
        settings.setAllowFileAccess(true);
        settings.setAllowContentAccess(true);
        settings.setMediaPlaybackRequiresUserGesture(false);
        settings.setMixedContentMode(WebSettings.MIXED_CONTENT_ALWAYS_ALLOW);

        CookieManager cookieManager = CookieManager.getInstance();
        cookieManager.setAcceptCookie(true);
        cookieManager.setAcceptThirdPartyCookies(webView, true);

        webView.setWebViewClient(new WebViewClient() {
            @Override
            public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                String url = request.getUrl().toString();
                if (url.startsWith("http://") || url.startsWith("https://")) {
                    return false;
                }
                try {
                    startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse(url)));
                } catch (Exception ignored) {
                }
                return true;
            }

            @Override
            public void onPageStarted(WebView view, String url, Bitmap favicon) {
                if (splashHidden) {
                    progressBar.setVisibility(View.VISIBLE);
                }
            }

            @Override
            public void onPageFinished(WebView view, String url) {
                progressBar.setVisibility(View.GONE);
                pageFinished = true;
                maybeHideSplash();
            }
        });

        webView.setWebChromeClient(new WebChromeClient() {
            @Override
            public void onProgressChanged(WebView view, int newProgress) {
                if (!splashHidden) {
                    return;
                }
                progressBar.setProgress(newProgress);
                progressBar.setVisibility(newProgress >= 100 ? View.GONE : View.VISIBLE);
            }
        });

        webView.setDownloadListener(new DownloadListener() {
            @Override
            public void onDownloadStart(String url, String userAgent, String contentDisposition,
                                        String mimeType, long contentLength) {
                Intent intent = new Intent(Intent.ACTION_VIEW);
                intent.setData(Uri.parse(url));
                startActivity(intent);
            }
        });

        getOnBackPressedDispatcher().addCallback(this, new OnBackPressedCallback(true) {
            @Override
            public void handleOnBackPressed() {
                if (webView.canGoBack()) {
                    webView.goBack();
                } else {
                    finish();
                }
            }
        });

        handler.postDelayed(() -> {
            minSplashElapsed = true;
            maybeHideSplash();
        }, MIN_SPLASH_MS);

        if (savedInstanceState == null) {
            webView.loadUrl(getString(R.string.app_url));
        } else {
            // Returning from rotation — skip splash
            pageFinished = true;
            minSplashElapsed = true;
            splashContainer.setVisibility(View.GONE);
            splashHidden = true;
        }
    }

    private void applySystemBarInsets(View root, View content) {
        ViewCompat.setOnApplyWindowInsetsListener(root, (v, insets) -> {
            Insets bars = insets.getInsets(WindowInsetsCompat.Type.systemBars());
            // Keep WebView clear of status/nav bars so notifications don't overlap content
            content.setPadding(bars.left, bars.top, bars.right, bars.bottom);
            // Splash stays edge-to-edge under the status bar for a full-bleed look,
            // but add bottom padding so the spinner isn't under gesture nav
            splashContainer.setPadding(0, 0, 0, bars.bottom);
            return insets;
        });
    }

    private void styleSystemBars() {
        int color = getResources().getColor(R.color.splash_background, getTheme());
        getWindow().setStatusBarColor(color);
        getWindow().setNavigationBarColor(color);

        double luminance = (0.299 * Color.red(color)
                + 0.587 * Color.green(color)
                + 0.114 * Color.blue(color)) / 255.0;
        boolean lightBackground = luminance > 0.62;

        WindowInsetsControllerCompat controller =
                WindowCompat.getInsetsController(getWindow(), getWindow().getDecorView());
        controller.setAppearanceLightStatusBars(lightBackground);
        controller.setAppearanceLightNavigationBars(lightBackground);

        ProgressBar splashSpinner = findViewById(R.id.splashSpinner);
        if (splashSpinner != null) {
            splashSpinner.setIndeterminateTintList(
                    android.content.res.ColorStateList.valueOf(
                            lightBackground ? Color.parseColor("#222222") : Color.WHITE));
        }
    }

    private void playSplashIntro() {
        splashLogo.setAlpha(0f);
        splashLogo.setScaleX(0.82f);
        splashLogo.setScaleY(0.82f);
        splashLogo.animate()
                .alpha(1f)
                .scaleX(1f)
                .scaleY(1f)
                .setDuration(700)
                .setInterpolator(new OvershootInterpolator(1.05f))
                .start();
    }

    private void maybeHideSplash() {
        if (splashHidden || !pageFinished || !minSplashElapsed) {
            return;
        }
        splashHidden = true;

        ObjectAnimator fade = ObjectAnimator.ofFloat(splashContainer, View.ALPHA, 1f, 0f);
        fade.setDuration(420);
        fade.setInterpolator(new DecelerateInterpolator());
        fade.addListener(new AnimatorListenerAdapter() {
            @Override
            public void onAnimationEnd(Animator animation) {
                splashContainer.setVisibility(View.GONE);
                splashContainer.setAlpha(1f);
            }
        });
        fade.start();
    }

    @Override
    protected void onDestroy() {
        handler.removeCallbacksAndMessages(null);
        super.onDestroy();
    }

    @Override
    protected void onSaveInstanceState(Bundle outState) {
        super.onSaveInstanceState(outState);
        webView.saveState(outState);
    }

    @Override
    protected void onRestoreInstanceState(Bundle savedInstanceState) {
        super.onRestoreInstanceState(savedInstanceState);
        webView.restoreState(savedInstanceState);
    }
}
