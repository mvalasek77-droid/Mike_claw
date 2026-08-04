import React, { useState } from "react";
import {
  View,
  Text,
  TextInput,
  FlatList,
  TouchableOpacity,
  StyleSheet,
} from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { Ionicons } from "@expo/vector-icons";
import * as Haptics from "expo-haptics";
import VideoCard from "../components/VideoCard";
import { searchVideos, THEME, type Video } from "../lib/data";

interface SearchScreenProps {
  onBack: () => void;
  onVideoPress: (video: Video) => void;
}

export default function SearchScreen({
  onBack,
  onVideoPress,
}: SearchScreenProps) {
  const [query, setQuery] = useState("");
  const results = query.trim() ? searchVideos(query) : [];

  return (
    <SafeAreaView style={styles.container} edges={["top"]}>
      <View style={styles.header}>
        <TouchableOpacity
          onPress={onBack}
          activeOpacity={0.6}
          accessibilityRole="button"
          accessibilityLabel="Go back"
        >
          <Ionicons name="arrow-back" size={24} color={THEME.textPrimary} />
        </TouchableOpacity>
        <View style={styles.searchBar}>
          <Ionicons name="search" size={18} color={THEME.textSecondary} />
          <TextInput
            style={styles.searchInput}
            placeholder="Search BannedTube"
            placeholderTextColor="#666"
            value={query}
            onChangeText={setQuery}
            autoFocus
            returnKeyType="search"
            accessibilityLabel="Search input"
            accessibilityHint="Type to search videos, channels, or topics"
          />
          {query.length > 0 && (
            <TouchableOpacity
              onPress={() => {
                Haptics.selectionAsync();
                setQuery("");
              }}
              accessibilityRole="button"
              accessibilityLabel="Clear search"
            >
              <Ionicons
                name="close-circle"
                size={18}
                color={THEME.textSecondary}
              />
            </TouchableOpacity>
          )}
        </View>
      </View>

      {query.trim() && (
        <Text style={styles.resultCount} accessibilityRole="text">
          {results.length} result{results.length !== 1 ? "s" : ""} for "
          {query}"
        </Text>
      )}

      <FlatList
        data={results}
        keyExtractor={(item) => item.id}
        renderItem={({ item }) => (
          <View style={styles.cardWrapper}>
            <VideoCard video={item} onPress={onVideoPress} layout="list" />
          </View>
        )}
        contentContainerStyle={styles.list}
        showsVerticalScrollIndicator={false}
        keyboardDismissMode="on-drag"
        ListEmptyComponent={
          query.trim() ? (
            <View style={styles.emptyContainer}>
              <Ionicons name="search" size={48} color={THEME.bgTertiary} />
              <Text style={styles.emptyText}>No results found</Text>
              <Text style={styles.emptySubtext}>Try different keywords</Text>
            </View>
          ) : (
            <View style={styles.emptyContainer}>
              <Ionicons name="search" size={48} color={THEME.bgTertiary} />
              <Text style={styles.emptyText}>
                Search for videos, channels, or topics
              </Text>
            </View>
          )
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
  header: {
    flexDirection: "row",
    alignItems: "center",
    paddingHorizontal: 14,
    paddingVertical: 10,
    gap: 12,
    borderBottomWidth: 1,
    borderBottomColor: THEME.border,
  },
  searchBar: {
    flex: 1,
    flexDirection: "row",
    alignItems: "center",
    backgroundColor: THEME.bgSecondary,
    borderRadius: 20,
    paddingHorizontal: 14,
    height: 40,
    gap: 8,
    borderWidth: 1,
    borderColor: THEME.border,
  },
  searchInput: {
    flex: 1,
    color: THEME.textPrimary,
    fontSize: 15,
  },
  resultCount: {
    color: THEME.textSecondary,
    fontSize: 13,
    paddingHorizontal: 14,
    paddingTop: 12,
    paddingBottom: 6,
  },
  list: {
    paddingBottom: 100,
  },
  cardWrapper: {
    paddingHorizontal: 14,
    paddingVertical: 4,
  },
  emptyContainer: {
    alignItems: "center",
    paddingTop: 80,
    gap: 12,
  },
  emptyText: {
    color: THEME.textSecondary,
    fontSize: 16,
  },
  emptySubtext: {
    color: THEME.textSecondary,
    fontSize: 13,
    opacity: 0.7,
  },
});
