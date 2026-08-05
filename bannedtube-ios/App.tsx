import React, { useState, useRef, useEffect } from "react";
import {
  View,
  Text,
  TouchableOpacity,
  StyleSheet,
  Animated,
  ActivityIndicator,
} from "react-native";
import { StatusBar } from "expo-status-bar";
import { SafeAreaProvider } from "react-native-safe-area-context";
import { LinearGradient } from "expo-linear-gradient";
import { BlurView } from "expo-blur";
import { Ionicons } from "@expo/vector-icons";
import * as Haptics from "expo-haptics";
import { AppProvider, useApp } from "./src/lib/AppContext";
import HomeScreen from "./src/screens/HomeScreen";
import WatchScreen from "./src/screens/WatchScreen";
import ChannelScreen from "./src/screens/ChannelScreen";
import SearchScreen from "./src/screens/SearchScreen";
import TrendingScreen from "./src/screens/TrendingScreen";
import SubscriptionsScreen from "./src/screens/SubscriptionsScreen";
import AIStudioScreen from "./src/screens/AIStudioScreen";
import LibraryScreen from "./src/screens/LibraryScreen";
import ShortsScreen from "./src/screens/ShortsScreen";
import YouScreen from "./src/screens/YouScreen";
import ErrorBoundary from "./src/components/ErrorBoundary";
import OnboardingScreen from "./src/screens/OnboardingScreen";
import { THEME, type Video, videos } from "./src/lib/data";

type Tab = "home" | "shorts" | "trending" | "subscriptions" | "studio" | "search" | "library" | "you";

type Overlay =
  | { type: "none" }
  | { type: "watch"; video: Video }
  | { type: "channel"; channelId: string };

const TAB_CONFIG: {
  key: Tab;
  icon: string;
  iconActive: string;
  label: string;
}[] = [
  { key: "home", icon: "home-outline", iconActive: "home", label: "Home" },
  {
    key: "shorts",
    icon: "flash-outline",
    iconActive: "flash",
    label: "Shorts",
  },
  {
    key: "trending",
    icon: "flame-outline",
    iconActive: "flame",
    label: "Trending",
  },
  {
    key: "studio",
    icon: "sparkles-outline",
    iconActive: "sparkles",
    label: "AI Studio",
  },
  {
    key: "subscriptions",
    icon: "people-outline",
    iconActive: "people",
    label: "Subs",
  },
  {
    key: "search",
    icon: "search-outline",
    iconActive: "search",
    label: "Search",
  },
  {
    key: "library",
    icon: "library-outline",
    iconActive: "library",
    label: "Library",
  },
  {
    key: "you",
    icon: "person-circle-outline",
    iconActive: "person-circle",
    label: "You",
  },
];

function AppContent() {
  const { ready, profile } = useApp();
  const [onboarded, setOnboarded] = useState(profile !== null);
  const [activeTab, setActiveTab] = useState<Tab>("home");
  const [overlay, setOverlay] = useState<Overlay>({ type: "none" });
  const [overlayHistory, setOverlayHistory] = useState<Overlay[]>([]);

  const tabIndicatorAnim = useRef(new Animated.Value(0)).current;

  useEffect(() => {
    const idx = TAB_CONFIG.findIndex((t) => t.key === activeTab);
    Animated.spring(tabIndicatorAnim, {
      toValue: idx,
      useNativeDriver: true,
      tension: 80,
      friction: 12,
    }).start();
  }, [activeTab]);

  if (ready && !onboarded && profile === null) {
    return (
      <OnboardingScreen onComplete={() => setOnboarded(true)} />
    );
  }

  if (!ready) {
    return (
      <View style={styles.loadingScreen}>
        <View style={styles.loadingLogo}>
          <Ionicons name="flame" size={32} color="#fff" />
        </View>
        <Text style={styles.loadingText}>
          Banned<Text style={{ color: THEME.accent }}>Tube</Text>
        </Text>
        <ActivityIndicator
          color={THEME.accent}
          size="small"
          style={{ marginTop: 24 }}
        />
      </View>
    );
  }

  function openOverlay(next: Overlay) {
    if (overlay.type !== "none") {
      setOverlayHistory((h) => [...h, overlay]);
    }
    setOverlay(next);
  }

  function closeOverlay() {
    const prev = overlayHistory[overlayHistory.length - 1];
    if (prev) {
      setOverlayHistory((h) => h.slice(0, -1));
      setOverlay(prev);
    } else {
      setOverlay({ type: "none" });
    }
  }

  const handleVideoPress = (v: Video) =>
    openOverlay({ type: "watch", video: v });
  const handleChannelPress = (id: string) =>
    openOverlay({ type: "channel", channelId: id });

  function handleTabPress(tab: Tab) {
    Haptics.selectionAsync();
    setActiveTab(tab);
  }

  return (
    <View style={styles.root}>
      <View style={styles.content}>
        {activeTab === "home" && (
          <HomeScreen
            onVideoPress={handleVideoPress}
            onChannelPress={handleChannelPress}
            onSearchPress={() => handleTabPress("search")}
          />
        )}
        {activeTab === "shorts" && (
          <ShortsScreen videos={videos.slice(0, 10)} />
        )}
        {activeTab === "trending" && (
          <TrendingScreen onVideoPress={handleVideoPress} />
        )}
        {activeTab === "studio" && <AIStudioScreen />}
        {activeTab === "subscriptions" && (
          <SubscriptionsScreen
            onVideoPress={handleVideoPress}
            onChannelPress={handleChannelPress}
          />
        )}
        {activeTab === "search" && (
          <SearchScreen
            onBack={() => handleTabPress("home")}
            onVideoPress={handleVideoPress}
          />
        )}
        {activeTab === "library" && (
          <LibraryScreen
            onVideoPress={handleVideoPress}
            onChannelPress={handleChannelPress}
          />
        )}
        {activeTab === "you" && (
          <YouScreen onChannelPress={handleChannelPress} />
        )}
      </View>

      {overlay.type === "watch" && (
        <View style={styles.overlay}>
          <WatchScreen
            video={overlay.video}
            onBack={closeOverlay}
            onVideoPress={handleVideoPress}
            onChannelPress={handleChannelPress}
          />
        </View>
      )}
      {overlay.type === "channel" && (
        <View style={styles.overlay}>
          <ChannelScreen
            channelId={overlay.channelId}
            onBack={closeOverlay}
            onVideoPress={handleVideoPress}
          />
        </View>
      )}

      {overlay.type === "none" && (
        <View style={styles.tabBarOuter}>
          <BlurView
            intensity={60}
            tint="dark"
            style={StyleSheet.absoluteFill}
          />
          <LinearGradient
            colors={["rgba(15,15,15,0.7)", "rgba(15,15,15,0.92)"]}
            style={StyleSheet.absoluteFill}
          />
          <View style={styles.tabBarBorderTop} />
          <View style={styles.tabBar}>
            {TAB_CONFIG.map((tab) => {
              const isActive = activeTab === tab.key;
              const isStudio = tab.key === "studio";
              return (
                <TouchableOpacity
                  key={tab.key}
                  style={styles.tabItem}
                  onPress={() => handleTabPress(tab.key)}
                  activeOpacity={0.6}
                  accessibilityRole="tab"
                  accessibilityState={{ selected: isActive }}
                  accessibilityLabel={`${tab.label} tab`}
                >
                  {isStudio ? (
                    <View
                      style={[
                        styles.studioIconWrap,
                        isActive && styles.studioIconWrapActive,
                      ]}
                    >
                      <Ionicons
                        name={(isActive ? tab.iconActive : tab.icon) as any}
                        size={20}
                        color={isActive ? "#fff" : THEME.textSecondary}
                      />
                    </View>
                  ) : (
                    <Ionicons
                      name={(isActive ? tab.iconActive : tab.icon) as any}
                      size={22}
                      color={isActive ? THEME.accent : THEME.textSecondary}
                    />
                  )}
                  <Text
                    style={[
                      styles.tabLabel,
                      isActive && !isStudio && styles.tabLabelActive,
                      isActive && isStudio && styles.tabLabelStudio,
                    ]}
                  >
                    {tab.label}
                  </Text>
                  {isActive && !isStudio && <View style={styles.tabDot} />}
                </TouchableOpacity>
              );
            })}
          </View>
        </View>
      )}
    </View>
  );
}

export default function App() {
  return (
    <SafeAreaProvider>
      <StatusBar style="light" />
      <AppProvider>
        <ErrorBoundary>
          <AppContent />
        </ErrorBoundary>
      </AppProvider>
    </SafeAreaProvider>
  );
}

const styles = StyleSheet.create({
  root: {
    flex: 1,
    backgroundColor: THEME.bgPrimary,
  },
  content: {
    flex: 1,
  },
  overlay: {
    position: "absolute",
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
    backgroundColor: THEME.bgPrimary,
  },
  loadingScreen: {
    flex: 1,
    backgroundColor: THEME.bgPrimary,
    justifyContent: "center",
    alignItems: "center",
  },
  loadingLogo: {
    width: 64,
    height: 64,
    borderRadius: 20,
    backgroundColor: THEME.accent,
    justifyContent: "center",
    alignItems: "center",
    shadowColor: THEME.accent,
    shadowOffset: { width: 0, height: 0 },
    shadowOpacity: 0.6,
    shadowRadius: 20,
  },
  loadingText: {
    color: THEME.textPrimary,
    fontSize: 28,
    fontWeight: "800",
    marginTop: 16,
    letterSpacing: -0.5,
  },
  tabBarOuter: {
    position: "absolute",
    bottom: 0,
    left: 0,
    right: 0,
    overflow: "hidden",
  },
  tabBarBorderTop: {
    height: 1,
    backgroundColor: "rgba(255,255,255,0.06)",
  },
  tabBar: {
    flexDirection: "row",
    paddingBottom: 28,
    paddingTop: 8,
    paddingHorizontal: 4,
  },
  tabItem: {
    flex: 1,
    alignItems: "center",
    gap: 2,
    position: "relative",
  },
  tabLabel: {
    color: THEME.textSecondary,
    fontSize: 10,
    fontWeight: "500",
    marginTop: 1,
  },
  tabLabelActive: {
    color: THEME.accent,
    fontWeight: "600",
  },
  tabLabelStudio: {
    color: THEME.accent,
    fontWeight: "600",
  },
  tabDot: {
    width: 4,
    height: 4,
    borderRadius: 2,
    backgroundColor: THEME.accent,
    marginTop: 2,
  },
  studioIconWrap: {
    width: 36,
    height: 28,
    borderRadius: 14,
    justifyContent: "center",
    alignItems: "center",
    backgroundColor: "transparent",
  },
  studioIconWrapActive: {
    backgroundColor: THEME.accent,
    shadowColor: THEME.accent,
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.5,
    shadowRadius: 8,
  },
});
