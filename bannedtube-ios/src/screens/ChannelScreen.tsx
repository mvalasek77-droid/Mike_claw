import React from "react";
import {
  View,
  Text,
  ScrollView,
  TouchableOpacity,
  StyleSheet,
} from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { LinearGradient } from "expo-linear-gradient";
import { Ionicons } from "@expo/vector-icons";
import Avatar from "../components/Avatar";
import VideoCard from "../components/VideoCard";
import {
  type Video,
  type Channel,
  getChannelById,
  getVideosByChannel,
  formatSubscribers,
  formatViews,
  THEME,
} from "../lib/data";

interface ChannelScreenProps {
  channelId: string;
  onBack: () => void;
  onVideoPress: (video: Video) => void;
}

export default function ChannelScreen({
  channelId,
  onBack,
  onVideoPress,
}: ChannelScreenProps) {
  const channel = getChannelById(channelId);
  const channelVideos = getVideosByChannel(channelId);

  if (!channel) {
    return (
      <SafeAreaView style={styles.container}>
        <Text style={styles.notFound}>Channel not found</Text>
      </SafeAreaView>
    );
  }

  const tabs = ["Videos", "Playlists", "Community", "About"];

  return (
    <SafeAreaView style={styles.container} edges={["top"]}>
      <ScrollView showsVerticalScrollIndicator={false}>
        {/* Banner with gradient masks */}
        <View style={styles.banner}>
          <LinearGradient
            colors={channel.bannerColors || ["#1a1a1a", "#0f0f0f", "#1a1a1a"]}
            start={{ x: 0, y: 0 }}
            end={{ x: 1, y: 1 }}
            style={StyleSheet.absoluteFill}
          />
          {/* Top fade mask */}
          <LinearGradient
            colors={["rgba(0,0,0,0.3)", "transparent"]}
            start={{ x: 0, y: 0 }}
            end={{ x: 0, y: 0.5 }}
            style={StyleSheet.absoluteFill}
          />
          {/* Bottom fade to content */}
          <LinearGradient
            colors={["transparent", THEME.bgPrimary]}
            start={{ x: 0, y: 0.6 }}
            end={{ x: 0, y: 1 }}
            style={StyleSheet.absoluteFill}
          />
          {/* Watermark name */}
          <Text style={styles.bannerWatermark}>{channel.name}</Text>

          {/* Back button */}
          <TouchableOpacity
            style={styles.backBtn}
            onPress={onBack}
            activeOpacity={0.6}
          >
            <Ionicons name="chevron-back" size={24} color={THEME.textPrimary} />
          </TouchableOpacity>
        </View>

        {/* Channel info */}
        <View style={styles.channelInfo}>
          <View style={styles.avatarContainer}>
            <Avatar
              color={channel.avatarColor}
              initial={channel.initial}
              size={72}
              borderColor="rgba(255,68,68,0.3)"
            />
            {/* Avatar glow */}
            <View
              style={[
                styles.avatarGlow,
                { backgroundColor: channel.avatarColor },
              ]}
            />
          </View>
          <View style={styles.infoText}>
            <View style={styles.nameRow}>
              <Text style={styles.channelName}>{channel.name}</Text>
              {channel.verified && (
                <Ionicons
                  name="checkmark-circle"
                  size={18}
                  color={THEME.textSecondary}
                />
              )}
            </View>
            <Text style={styles.stats}>
              {formatSubscribers(channel.subscribers)} ·{" "}
              {channelVideos.length} videos
              {channel.totalViews
                ? ` · ${formatViews(channel.totalViews)} total`
                : ""}
            </Text>
            {channel.description && (
              <Text style={styles.description} numberOfLines={2}>
                {channel.description}
              </Text>
            )}
          </View>
        </View>

        {/* Action buttons */}
        <View style={styles.actionsRow}>
          <TouchableOpacity style={styles.subscribeBtn} activeOpacity={0.7}>
            <Text style={styles.subscribeBtnText}>Subscribe</Text>
          </TouchableOpacity>
          <TouchableOpacity style={styles.bellBtn} activeOpacity={0.7}>
            <Ionicons
              name="notifications-outline"
              size={20}
              color={THEME.textPrimary}
            />
          </TouchableOpacity>
        </View>

        {/* Tabs */}
        <ScrollView
          horizontal
          showsHorizontalScrollIndicator={false}
          contentContainerStyle={styles.tabsRow}
        >
          {tabs.map((tab, i) => (
            <TouchableOpacity key={tab} style={styles.tab} activeOpacity={0.7}>
              <Text
                style={[styles.tabText, i === 0 && styles.tabTextActive]}
              >
                {tab}
              </Text>
              {i === 0 && <View style={styles.tabIndicator} />}
            </TouchableOpacity>
          ))}
        </ScrollView>

        <View style={styles.divider} />

        {/* Videos */}
        <View style={styles.videosContainer}>
          {channelVideos.map((video) => (
            <VideoCard
              key={video.id}
              video={video}
              onPress={onVideoPress}
            />
          ))}
          {channelVideos.length === 0 && (
            <Text style={styles.emptyText}>No videos yet</Text>
          )}
        </View>

        <View style={{ height: 40 }} />
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: THEME.bgPrimary,
  },
  notFound: {
    color: THEME.textSecondary,
    fontSize: 16,
    textAlign: "center",
    marginTop: 100,
  },
  banner: {
    height: 140,
    justifyContent: "center",
    alignItems: "center",
    position: "relative",
  },
  bannerWatermark: {
    color: "rgba(255,255,255,0.06)",
    fontSize: 48,
    fontWeight: "800",
    textAlign: "center",
  },
  backBtn: {
    position: "absolute",
    top: 12,
    left: 12,
    width: 36,
    height: 36,
    borderRadius: 18,
    backgroundColor: "rgba(0,0,0,0.4)",
    justifyContent: "center",
    alignItems: "center",
  },
  channelInfo: {
    flexDirection: "row",
    paddingHorizontal: 16,
    gap: 14,
    marginTop: -10,
  },
  avatarContainer: {
    position: "relative",
  },
  avatarGlow: {
    position: "absolute",
    width: 72,
    height: 72,
    borderRadius: 36,
    opacity: 0.15,
    top: 4,
    left: 4,
    transform: [{ scale: 1.2 }],
  },
  infoText: {
    flex: 1,
    justifyContent: "center",
  },
  nameRow: {
    flexDirection: "row",
    alignItems: "center",
    gap: 6,
  },
  channelName: {
    color: THEME.textPrimary,
    fontSize: 20,
    fontWeight: "700",
  },
  stats: {
    color: THEME.textSecondary,
    fontSize: 12,
    marginTop: 4,
  },
  description: {
    color: THEME.textSecondary,
    fontSize: 13,
    marginTop: 4,
    lineHeight: 18,
  },
  actionsRow: {
    flexDirection: "row",
    paddingHorizontal: 16,
    gap: 10,
    marginTop: 14,
  },
  subscribeBtn: {
    backgroundColor: THEME.accent,
    paddingHorizontal: 24,
    paddingVertical: 10,
    borderRadius: 22,
  },
  subscribeBtnText: {
    color: "#fff",
    fontSize: 14,
    fontWeight: "600",
  },
  bellBtn: {
    width: 40,
    height: 40,
    borderRadius: 20,
    backgroundColor: THEME.bgTertiary,
    justifyContent: "center",
    alignItems: "center",
  },
  tabsRow: {
    paddingHorizontal: 16,
    gap: 24,
    marginTop: 18,
  },
  tab: {
    paddingBottom: 10,
    position: "relative",
  },
  tabText: {
    color: THEME.textSecondary,
    fontSize: 14,
    fontWeight: "500",
  },
  tabTextActive: {
    color: THEME.textPrimary,
  },
  tabIndicator: {
    position: "absolute",
    bottom: 0,
    left: 0,
    right: 0,
    height: 2,
    backgroundColor: THEME.textPrimary,
    borderRadius: 1,
  },
  divider: {
    height: 1,
    backgroundColor: THEME.border,
    marginBottom: 16,
  },
  videosContainer: {
    paddingHorizontal: 12,
  },
  emptyText: {
    color: THEME.textSecondary,
    textAlign: "center",
    marginTop: 40,
    fontSize: 15,
  },
});
