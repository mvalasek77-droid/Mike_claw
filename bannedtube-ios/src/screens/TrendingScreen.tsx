import React from "react";
import {
  View,
  Text,
  FlatList,
  TouchableOpacity,
  StyleSheet,
} from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { LinearGradient } from "expo-linear-gradient";
import { Ionicons } from "@expo/vector-icons";
import VideoCard from "../components/VideoCard";
import { videos, THEME, type Video } from "../lib/data";

interface TrendingScreenProps {
  onVideoPress: (video: Video) => void;
}

export default function TrendingScreen({ onVideoPress }: TrendingScreenProps) {
  const trending = [...videos].sort((a, b) => b.views - a.views);

  return (
    <SafeAreaView style={styles.container} edges={["top"]}>
      <View style={styles.header}>
        <Ionicons name="trending-up" size={24} color={THEME.accent} />
        <Text style={styles.headerTitle}>Trending</Text>
      </View>

      <FlatList
        data={trending}
        keyExtractor={(item) => item.id}
        renderItem={({ item, index }) => (
          <View style={styles.row}>
            <View style={styles.rankContainer}>
              <Text
                style={[
                  styles.rank,
                  index < 3 && { color: THEME.accent },
                ]}
              >
                {index + 1}
              </Text>
              {index < 3 && (
                <Ionicons name="flame" size={12} color={THEME.accent} />
              )}
            </View>
            <View style={styles.cardWrapper}>
              <VideoCard video={item} onPress={onVideoPress} layout="list" />
            </View>
          </View>
        )}
        ItemSeparatorComponent={() => <View style={styles.separator} />}
        contentContainerStyle={styles.list}
        showsVerticalScrollIndicator={false}
      />
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: THEME.bgPrimary,
  },
  header: {
    flexDirection: "row",
    alignItems: "center",
    gap: 10,
    paddingHorizontal: 16,
    paddingVertical: 14,
    borderBottomWidth: 1,
    borderBottomColor: THEME.border,
  },
  headerTitle: {
    color: THEME.textPrimary,
    fontSize: 20,
    fontWeight: "700",
  },
  list: {
    paddingBottom: 100,
  },
  row: {
    flexDirection: "row",
    alignItems: "center",
    paddingHorizontal: 8,
  },
  rankContainer: {
    width: 36,
    alignItems: "center",
    gap: 2,
  },
  rank: {
    color: THEME.textSecondary,
    fontSize: 18,
    fontWeight: "700",
  },
  cardWrapper: {
    flex: 1,
  },
  separator: {
    height: 1,
    backgroundColor: THEME.border,
    marginHorizontal: 16,
    marginVertical: 4,
    opacity: 0.5,
  },
});
