import React, { useState } from "react";
import { StatusBar } from "expo-status-bar";
import { SafeAreaProvider } from "react-native-safe-area-context";
import HomeScreen from "./src/screens/HomeScreen";
import WatchScreen from "./src/screens/WatchScreen";
import ChannelScreen from "./src/screens/ChannelScreen";
import SearchScreen from "./src/screens/SearchScreen";
import { type Video } from "./src/lib/data";

type Screen =
  | { type: "home" }
  | { type: "watch"; video: Video }
  | { type: "channel"; channelId: string }
  | { type: "search" };

export default function App() {
  const [screen, setScreen] = useState<Screen>({ type: "home" });
  const [history, setHistory] = useState<Screen[]>([]);

  function navigate(next: Screen) {
    setHistory((h) => [...h, screen]);
    setScreen(next);
  }

  function goBack() {
    const prev = history[history.length - 1];
    if (prev) {
      setHistory((h) => h.slice(0, -1));
      setScreen(prev);
    }
  }

  return (
    <SafeAreaProvider>
      <StatusBar style="light" />
      {screen.type === "home" && (
        <HomeScreen
          onVideoPress={(v) => navigate({ type: "watch", video: v })}
          onChannelPress={(id) => navigate({ type: "channel", channelId: id })}
          onSearchPress={() => navigate({ type: "search" })}
        />
      )}
      {screen.type === "watch" && (
        <WatchScreen
          video={screen.video}
          onBack={goBack}
          onVideoPress={(v) => navigate({ type: "watch", video: v })}
          onChannelPress={(id) => navigate({ type: "channel", channelId: id })}
        />
      )}
      {screen.type === "channel" && (
        <ChannelScreen
          channelId={screen.channelId}
          onBack={goBack}
          onVideoPress={(v) => navigate({ type: "watch", video: v })}
        />
      )}
      {screen.type === "search" && (
        <SearchScreen
          onBack={goBack}
          onVideoPress={(v) => navigate({ type: "watch", video: v })}
        />
      )}
    </SafeAreaProvider>
  );
}
