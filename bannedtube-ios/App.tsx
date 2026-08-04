import React, { useState } from "react";
import {
  View,
  Text,
  TouchableOpacity,
  StyleSheet,
  Dimensions,
} from "react-native";
import { StatusBar } from "expo-status-bar";
import { SafeAreaProvider } from "react-native-safe-area-context";
import { LinearGradient } from "expo-linear-gradient";
import { Ionicons } from "@expo/vector-icons";
import HomeScreen from "./src/screens/HomeScreen";
import WatchScreen from "./src/screens/WatchScreen";
import ChannelScreen from "./src/screens/ChannelScreen";
import SearchScreen from "./src/screens/SearchScreen";
import TrendingScreen from "./src/screens/TrendingScreen";
import SubscriptionsScreen from "./src/screens/SubscriptionsScreen";
import { THEME, type Video } from "./src/lib/data";

type Tab = "home" | "trending" | "subscriptions" | "search";

type Overlay =
  | { type: "none" }
  | { type: "watch"; video: Video }
  | { type: "channel"; channelId: string };

const TAB_CONFIG: { key: Tab; icon: string; iconActive: string; label: string }[] = [
  { key: "home", icon: "home-outline", iconActive: "home", label: "Home" },
  { key: "trending", icon: "flame-outline", iconActive: "flame", label: "Trending" },
  { key: "subscriptions", icon: "people-outline", iconActive: "people", label: "Subscriptions" },
  { key: "search", icon: "search-outline", iconActive: "search", label: "Search" },
];

export default function App() {
  const [activeTab, setActiveTab] = useState<Tab>("home");
  const [overlay, setOverlay] = useState<Overlay>({ type: "none" });
  const [overlayHistory, setOverlayHistory] = useState<Overlay[]>([]);

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

  return (
    <SafeAreaProvider>
      <StatusBar style="light" />
      <View style={styles.root}>
        {/* Tab content */}
        <View style={styles.content}>
          {activeTab === "home" && (
            <HomeScreen
              onVideoPress={handleVideoPress}
              onChannelPress={handleChannelPress}
              onSearchPress={() => setActiveTab("search")}
            />
          )}
          {activeTab === "trending" && (
            <TrendingScreen onVideoPress={handleVideoPress} />
          )}
          {activeTab === "subscriptions" && (
            <SubscriptionsScreen
              onVideoPress={handleVideoPress}
              onChannelPress={handleChannelPress}
            />
          )}
          {activeTab === "search" && (
            <SearchScreen
              onBack={() => setActiveTab("home")}
              onVideoPress={handleVideoPress}
            />
          )}
        </View>

        {/* Overlay screens (watch/channel) sit on top */}
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

        {/* Bottom tab bar */}
        {overlay.type === "none" && (
          <View style={styles.tabBarContainer}>
            <LinearGradient
              colors={["transparent", "rgba(0,0,0,0.85)", "rgba(0,0,0,0.95)"]}
              style={styles.tabBarGradient}
            />
            <View style={styles.tabBar}>
              {TAB_CONFIG.map((tab) => {
                const isActive = activeTab === tab.key;
                return (
                  <TouchableOpacity
                    key={tab.key}
                    style={styles.tabItem}
                    onPress={() => setActiveTab(tab.key)}
                    activeOpacity={0.6}
                  >
                    <Ionicons
                      name={(isActive ? tab.iconActive : tab.icon) as any}
                      size={22}
                      color={isActive ? THEME.accent : THEME.textSecondary}
                    />
                    <Text
                      style={[
                        styles.tabLabel,
                        isActive && styles.tabLabelActive,
                      ]}
                    >
                      {tab.label}
                    </Text>
                    {isActive && <View style={styles.tabDot} />}
                  </TouchableOpacity>
                );
              })}
            </View>
          </View>
        )}
      </View>
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
  tabBarContainer: {
    position: "absolute",
    bottom: 0,
    left: 0,
    right: 0,
  },
  tabBarGradient: {
    position: "absolute",
    bottom: 0,
    left: 0,
    right: 0,
    height: 100,
  },
  tabBar: {
    flexDirection: "row",
    paddingBottom: 28,
    paddingTop: 8,
    paddingHorizontal: 8,
    borderTopWidth: 1,
    borderTopColor: "rgba(255,255,255,0.08)",
  },
  tabItem: {
    flex: 1,
    alignItems: "center",
    gap: 3,
    position: "relative",
  },
  tabLabel: {
    color: THEME.textSecondary,
    fontSize: 10,
    fontWeight: "500",
  },
  tabLabelActive: {
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
});
