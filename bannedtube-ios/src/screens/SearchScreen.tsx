import React, { useState } from "react";
import {
  View,
  Text,
  TextInput,
  FlatList,
  TouchableOpacity,
  StyleSheet,
  ScrollView,
} from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { Ionicons } from "@expo/vector-icons";
import * as Haptics from "expo-haptics";
import VideoCard from "../components/VideoCard";
import { useApp } from "../lib/AppContext";
import { searchVideos, THEME, type Video } from "../lib/data";

const TRENDING_SEARCHES = [
  "documentary",
  "comedy",
  "investigation",
  "independent media",
  "censorship",
  "free speech",
  "wellness",
  "technology",
];

interface SearchScreenProps {
  onBack: () => void;
  onVideoPress: (video: Video) => void;
}

export default function SearchScreen({
  onBack,
  onVideoPress,
}: SearchScreenProps) {
  const { recentSearches, addRecentSearch, clearRecentSearches } = useApp();
  const [query, setQuery] = useState("");
  const [hasSearched, setHasSearched] = useState(false);
  const results = query.trim() ? searchVideos(query) : [];

  function handleSubmit() {
    if (query.trim()) {
      Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
      addRecentSearch(query.trim());
      setHasSearched(true);
    }
  }

  function quickSearch(term: string) {
    setQuery(term);
    addRecentSearch(term);
    setHasSearched(true);
    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
  }

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
            onChangeText={(t) => {
              setQuery(t);
              if (!t.trim()) setHasSearched(false);
            }}
            autoFocus
            returnKeyType="search"
            onSubmitEditing={handleSubmit}
            accessibilityLabel="Search input"
            accessibilityHint="Type to search videos, channels, or topics"
          />
          {query.length > 0 && (
            <TouchableOpacity
              onPress={() => {
                setQuery("");
                setHasSearched(false);
              }}
              accessibilityLabel="Clear search"
            >
              <Ionicons name="close-circle" size={18} color={THEME.textSecondary} />
            </TouchableOpacity>
          )}
        </View>
      </View>

      {!hasSearched && !query.trim() ? (
        <ScrollView showsVerticalScrollIndicator={false}>
          {recentSearches.length > 0 && (
            <View style={styles.suggestionSection}>
              <View style={styles.suggestionHeader}>
                <Text style={styles.suggestionTitle}>Recent searches</Text>
                <TouchableOpacity
                  onPress={clearRecentSearches}
                  accessibilityLabel="Clear recent searches"
                >
                  <Text style={styles.clearText}>Clear</Text>
                </TouchableOpacity>
              </View>
              {recentSearches.map((term, i) => (
                <TouchableOpacity
                  key={i}
                  style={styles.recentItem}
                  onPress={() => quickSearch(term)}
                  accessibilityRole="button"
                  accessibilityLabel={`Search for ${term}`}
                >
                  <Ionicons name="time-outline" size={18} color={THEME.textSecondary} />
                  <Text style={styles.recentText}>{term}</Text>
                  <Ionicons name="arrow-forward" size={14} color={THEME.bgTertiary} />
                </TouchableOpacity>
              ))}
            </View>
          )}
          <View style={styles.suggestionSection}>
            <Text style={styles.suggestionTitle}>Trending searches</Text>
            {TRENDING_SEARCHES.map((term, i) => (
              <TouchableOpacity
                key={i}
                style={styles.recentItem}
                onPress={() => quickSearch(term)}
                accessibilityRole="button"
                accessibilityLabel={`Search for ${term}`}
              >
                <Ionicons name="trending-up" size={18} color={THEME.accent} />
                <Text style={styles.recentText}>{term}</Text>
                <Ionicons name="arrow-forward" size={14} color={THEME.bgTertiary} />
              </TouchableOpacity>
            ))}
          </View>
        </ScrollView>
      ) : (
        <FlatList
          data={results}
          keyExtractor={(item) => item.id}
          renderItem={({ item }) => (
            <View style={styles.cardWrapper}>
              <VideoCard
                video={item}
                onPress={onVideoPress}
                layout="list"
              />
            </View>
          )}
          ListHeaderComponent={
            results.length > 0 ? (
              <Text style={styles.resultCount}>
                {results.length} {results.length === 1 ? "result" : "results"}
              </Text>
            ) : null
          }
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
      )}
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
  suggestionSection: {
    paddingHorizontal: 16,
    paddingTop: 20,
  },
  suggestionHeader: {
    flexDirection: "row",
    justifyContent: "space-between",
    alignItems: "center",
  },
  suggestionTitle: {
    color: THEME.textPrimary,
    fontSize: 16,
    fontWeight: "700",
    marginBottom: 12,
  },
  clearText: {
    color: THEME.accent,
    fontSize: 13,
    fontWeight: "600",
  },
  recentItem: {
    flexDirection: "row",
    alignItems: "center",
    gap: 12,
    paddingVertical: 12,
    borderBottomWidth: 1,
    borderBottomColor: THEME.border,
  },
  recentText: {
    color: THEME.textPrimary,
    fontSize: 14,
    flex: 1,
  },
});
