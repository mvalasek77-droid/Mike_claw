import React, { useState, useCallback } from "react";
import {
  View,
  Text,
  FlatList,
  StyleSheet,
  RefreshControl,
} from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import Header from "../components/Header";
import CategoryBar from "../components/CategoryBar";
import VideoCard from "../components/VideoCard";
import { getVideosByCategory, THEME, type Video } from "../lib/data";

interface HomeScreenProps {
  onVideoPress: (video: Video) => void;
  onChannelPress: (channelId: string) => void;
  onSearchPress: () => void;
  onProfilePress: () => void;
}

export default function HomeScreen({
  onVideoPress,
  onChannelPress,
  onSearchPress,
  onProfilePress,
}: HomeScreenProps) {
  const [category, setCategory] = useState("All");
  const [refreshing, setRefreshing] = useState(false);

  const onRefresh = useCallback(() => {
    setRefreshing(true);
    setTimeout(() => setRefreshing(false), 1000);
  }, []);
  const filteredVideos = getVideosByCategory(category);

  return (
    <SafeAreaView style={styles.container} edges={["top"]}>
      <Header onSearch={onSearchPress} onProfile={onProfilePress} />
      <FlatList
        data={filteredVideos}
        keyExtractor={(item) => item.id}
        ListHeaderComponent={
          <CategoryBar active={category} onChange={setCategory} />
        }
        renderItem={({ item }) => (
          <View style={styles.cardWrapper}>
            <VideoCard
              video={item}
              onPress={onVideoPress}
              onChannelPress={onChannelPress}
            />
          </View>
        )}
        ListEmptyComponent={
          <View style={styles.empty}>
            <Text style={styles.emptyTitle}>Nothing in {category} yet</Text>
            <Text style={styles.emptyBody}>
              Try another category, or pull down to refresh.
            </Text>
          </View>
        }
        contentContainerStyle={styles.list}
        showsVerticalScrollIndicator={false}
        refreshControl={
          <RefreshControl
            refreshing={refreshing}
            onRefresh={onRefresh}
            tintColor={THEME.accent}
            colors={[THEME.accent]}
          />
        }
      />
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: THEME.bgPrimary,
  },
  list: {
    paddingBottom: 80,
  },
  cardWrapper: {
    paddingHorizontal: 12,
  },
  empty: {
    alignItems: "center",
    paddingTop: 70,
    paddingHorizontal: 40,
    gap: 6,
  },
  emptyTitle: {
    color: THEME.textPrimary,
    fontSize: 16,
    fontWeight: "600",
  },
  emptyBody: {
    color: THEME.textSecondary,
    fontSize: 14,
    textAlign: "center",
  },
});
