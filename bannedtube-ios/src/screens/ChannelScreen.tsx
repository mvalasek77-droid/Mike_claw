import React, { useState } from "react";
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
import * as Haptics from "expo-haptics";
import Avatar from "../components/Avatar";
import VideoCard from "../components/VideoCard";
import GlassCard from "../components/GlassCard";
import { useApp } from "../lib/AppContext";
import {
  type Video,
  getChannelById,
  getVideosByChannel,
  formatSubscribers,
  formatViews,
  formatCompact,
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
  const { isSubscribed, toggleSubscription } = useApp();
  const channel = getChannelById(channelId);
  const channelVideos = getVideosByChannel(channelId);
  const subscribed = isSubscribed(channelId);
  const [activeTab, setActiveTab] = useState(0);

  if (!channel) {
    return (
      <SafeAreaView style={styles.container}>
        <Text style={styles.notFound}>Channel not found</Text>
      </SafeAreaView>
    );
  }

  const tabs = ["Uploads", "Collections", "Feed", "Info"];

  async function handleSubscribe() {
    await toggleSubscription(channelId);
  }

  return (
    <SafeAreaView style={styles.container} edges={["top"]}>
      <ScrollView showsVerticalScrollIndicator={false}>
        <View style={styles.banner}>
          <LinearGradient
            colors={channel.bannerColors || ["#1a1a1a", "#0f0f0f", "#1a1a1a"]}
            start={{ x: 0, y: 0 }}
            end={{ x: 1, y: 1 }}
            style={StyleSheet.absoluteFill}
          />
          <LinearGradient
            colors={["rgba(0,0,0,0.3)", "transparent"]}
            start={{ x: 0, y: 0 }}
            end={{ x: 0, y: 0.5 }}
            style={StyleSheet.absoluteFill}
          />
          <LinearGradient
            colors={["transparent", THEME.bgPrimary]}
            start={{ x: 0, y: 0.6 }}
            end={{ x: 0, y: 1 }}
            style={StyleSheet.absoluteFill}
          />
          <Text
            style={styles.bannerWatermark}
            allowFontScaling={false}
          >
            {channel.name}
          </Text>

          <TouchableOpacity
            style={styles.backBtn}
            onPress={onBack}
            activeOpacity={0.6}
            accessibilityRole="button"
            accessibilityLabel="Go back"
          >
            <Ionicons
              name="chevron-back"
              size={24}
              color={THEME.textPrimary}
            />
          </TouchableOpacity>
        </View>

        <View style={styles.channelInfo}>
          <View style={styles.avatarContainer}>
            <Avatar
              color={channel.avatarColor}
              initial={channel.initial}
              size={72}
              borderColor="rgba(255,68,68,0.3)"
            />
            <View
              style={[
                styles.avatarGlow,
                { backgroundColor: channel.avatarColor },
              ]}
            />
          </View>
          <View style={styles.infoText}>
            <View style={styles.nameRow}>
              <Text
                style={styles.channelName}
                accessibilityRole="header"
              >
                {channel.name}
              </Text>
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

        <View style={styles.actionsRow}>
          <TouchableOpacity
            style={[
              styles.subscribeBtn,
              subscribed && styles.subscribedBtn,
            ]}
            onPress={handleSubscribe}
            activeOpacity={0.7}
            accessibilityRole="button"
            accessibilityLabel={subscribed ? "Unfollow" : "Follow"}
          >
            <Text
              style={[
                styles.subscribeBtnText,
                subscribed && styles.subscribedBtnText,
              ]}
            >
              {subscribed ? "Following" : "Follow"}
            </Text>
          </TouchableOpacity>
          <TouchableOpacity
            style={styles.bellBtn}
            activeOpacity={0.7}
            accessibilityRole="button"
            accessibilityLabel="Notification settings"
          >
            <Ionicons
              name={
                subscribed ? "notifications" : "notifications-outline"
              }
              size={20}
              color={THEME.textPrimary}
            />
          </TouchableOpacity>
        </View>

        <ScrollView
          horizontal
          showsHorizontalScrollIndicator={false}
          contentContainerStyle={styles.tabsRow}
        >
          {tabs.map((tab, i) => (
            <TouchableOpacity
              key={tab}
              style={styles.tab}
              activeOpacity={0.7}
              onPress={() => {
                Haptics.selectionAsync();
                setActiveTab(i);
              }}
              accessibilityRole="tab"
              accessibilityState={{ selected: activeTab === i }}
              accessibilityLabel={`${tab} tab`}
            >
              <Text
                style={[
                  styles.tabText,
                  activeTab === i && styles.tabTextActive,
                ]}
              >
                {tab}
              </Text>
              {activeTab === i && <View style={styles.tabIndicator} />}
            </TouchableOpacity>
          ))}
        </ScrollView>

        <View style={styles.divider} />

        {activeTab === 0 && (
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
        )}

        {activeTab === 1 && (
          <View style={styles.tabContent}>
            <GlassCard style={styles.playlistCard}>
              <View style={styles.playlistRow}>
                <Ionicons name="list" size={20} color={THEME.accent} />
                <View style={{ flex: 1 }}>
                  <Text style={styles.playlistTitle}>All Content</Text>
                  <Text style={styles.playlistMeta}>{channelVideos.length} videos</Text>
                </View>
                <Ionicons name="chevron-forward" size={18} color={THEME.textSecondary} />
              </View>
            </GlassCard>
            <GlassCard style={styles.playlistCard}>
              <View style={styles.playlistRow}>
                <Ionicons name="flame" size={20} color="#fbbf24" />
                <View style={{ flex: 1 }}>
                  <Text style={styles.playlistTitle}>Top Viewed</Text>
                  <Text style={styles.playlistMeta}>{Math.min(channelVideos.length, 5)} videos</Text>
                </View>
                <Ionicons name="chevron-forward" size={18} color={THEME.textSecondary} />
              </View>
            </GlassCard>
            <GlassCard style={styles.playlistCard}>
              <View style={styles.playlistRow}>
                <Ionicons name="time" size={20} color="#60a5fa" />
                <View style={{ flex: 1 }}>
                  <Text style={styles.playlistTitle}>Latest Drops</Text>
                  <Text style={styles.playlistMeta}>{Math.min(channelVideos.length, 3)} videos</Text>
                </View>
                <Ionicons name="chevron-forward" size={18} color={THEME.textSecondary} />
              </View>
            </GlassCard>
          </View>
        )}

        {activeTab === 2 && (
          <View style={styles.tabContent}>
            <GlassCard style={styles.communityPost}>
              <View style={styles.communityHeader}>
                <Avatar color={channel.avatarColor} initial={channel.initial} size={32} />
                <View>
                  <Text style={styles.communityAuthor}>{channel.name}</Text>
                  <Text style={styles.communityTime}>2 days ago</Text>
                </View>
              </View>
              <Text style={styles.communityText}>
                Big things coming this week! Stay tuned for a major announcement. Drop a fire emoji if you're ready.
              </Text>
              <View style={styles.communityActions}>
                <View style={styles.communityAction}>
                  <Ionicons name="thumbs-up-outline" size={16} color={THEME.textSecondary} />
                  <Text style={styles.communityActionText}>842</Text>
                </View>
                <View style={styles.communityAction}>
                  <Ionicons name="chatbubble-outline" size={16} color={THEME.textSecondary} />
                  <Text style={styles.communityActionText}>56</Text>
                </View>
              </View>
            </GlassCard>
            <GlassCard style={styles.communityPost}>
              <View style={styles.communityHeader}>
                <Avatar color={channel.avatarColor} initial={channel.initial} size={32} />
                <View>
                  <Text style={styles.communityAuthor}>{channel.name}</Text>
                  <Text style={styles.communityTime}>1 week ago</Text>
                </View>
              </View>
              <Text style={styles.communityText}>
                Thank you for {formatCompact(channel.subscribers)} subs! This community is incredible. What content do you want to see next?
              </Text>
              <View style={styles.communityActions}>
                <View style={styles.communityAction}>
                  <Ionicons name="thumbs-up-outline" size={16} color={THEME.textSecondary} />
                  <Text style={styles.communityActionText}>1.2K</Text>
                </View>
                <View style={styles.communityAction}>
                  <Ionicons name="chatbubble-outline" size={16} color={THEME.textSecondary} />
                  <Text style={styles.communityActionText}>203</Text>
                </View>
              </View>
            </GlassCard>
          </View>
        )}

        {activeTab === 3 && (
          <View style={styles.tabContent}>
            <GlassCard style={styles.aboutCard}>
              <Text style={styles.aboutLabel}>Description</Text>
              <Text style={styles.aboutText}>
                {channel.description || `Welcome to ${channel.name}. Follow for the latest content that the mainstream doesn't want you to see.`}
              </Text>
            </GlassCard>
            <GlassCard style={styles.aboutCard}>
              <Text style={styles.aboutLabel}>Stats</Text>
              <View style={styles.aboutStatsGrid}>
                <View style={styles.aboutStat}>
                  <Text style={styles.aboutStatVal}>{formatSubscribers(channel.subscribers)}</Text>
                  <Text style={styles.aboutStatKey}>Followers</Text>
                </View>
                <View style={styles.aboutStat}>
                  <Text style={styles.aboutStatVal}>{channelVideos.length}</Text>
                  <Text style={styles.aboutStatKey}>Videos</Text>
                </View>
                <View style={styles.aboutStat}>
                  <Text style={styles.aboutStatVal}>{channel.totalViews ? formatViews(channel.totalViews) : "N/A"}</Text>
                  <Text style={styles.aboutStatKey}>Total views</Text>
                </View>
              </View>
            </GlassCard>
            <GlassCard style={styles.aboutCard}>
              <Text style={styles.aboutLabel}>Details</Text>
              <View style={styles.aboutDetail}>
                <Ionicons name="globe-outline" size={16} color={THEME.textSecondary} />
                <Text style={styles.aboutDetailText}>bannedtube.app/{channel.name.toLowerCase().replace(/\s+/g, "")}</Text>
              </View>
              <View style={styles.aboutDetail}>
                <Ionicons name="calendar-outline" size={16} color={THEME.textSecondary} />
                <Text style={styles.aboutDetailText}>Joined Jan 2024</Text>
              </View>
              <View style={styles.aboutDetail}>
                <Ionicons name="location-outline" size={16} color={THEME.textSecondary} />
                <Text style={styles.aboutDetailText}>United States</Text>
              </View>
            </GlassCard>
          </View>
        )}

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
    shadowColor: THEME.accent,
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.3,
    shadowRadius: 8,
  },
  subscribedBtn: {
    backgroundColor: THEME.bgTertiary,
    borderWidth: 1,
    borderColor: THEME.border,
    shadowOpacity: 0,
  },
  subscribeBtnText: {
    color: "#fff",
    fontSize: 14,
    fontWeight: "600",
  },
  subscribedBtnText: {
    color: THEME.textSecondary,
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
  tabContent: {
    paddingHorizontal: 16,
    gap: 12,
  },
  playlistCard: {
    padding: 0,
  },
  playlistRow: {
    flexDirection: "row",
    alignItems: "center",
    gap: 12,
    padding: 14,
  },
  playlistTitle: {
    color: THEME.textPrimary,
    fontSize: 15,
    fontWeight: "600",
  },
  playlistMeta: {
    color: THEME.textSecondary,
    fontSize: 12,
    marginTop: 2,
  },
  communityPost: {
    gap: 10,
  },
  communityHeader: {
    flexDirection: "row",
    alignItems: "center",
    gap: 10,
  },
  communityAuthor: {
    color: THEME.textPrimary,
    fontSize: 14,
    fontWeight: "600",
  },
  communityTime: {
    color: THEME.textSecondary,
    fontSize: 11,
  },
  communityText: {
    color: THEME.textPrimary,
    fontSize: 14,
    lineHeight: 20,
  },
  communityActions: {
    flexDirection: "row",
    gap: 20,
    paddingTop: 4,
  },
  communityAction: {
    flexDirection: "row",
    alignItems: "center",
    gap: 4,
  },
  communityActionText: {
    color: THEME.textSecondary,
    fontSize: 12,
  },
  aboutCard: {
    gap: 10,
  },
  aboutLabel: {
    color: THEME.textSecondary,
    fontSize: 11,
    fontWeight: "600",
    textTransform: "uppercase",
    letterSpacing: 0.5,
  },
  aboutText: {
    color: THEME.textPrimary,
    fontSize: 14,
    lineHeight: 20,
  },
  aboutStatsGrid: {
    flexDirection: "row",
    gap: 16,
  },
  aboutStat: {
    flex: 1,
    alignItems: "center",
    paddingVertical: 8,
    backgroundColor: "rgba(255,255,255,0.03)",
    borderRadius: 8,
  },
  aboutStatVal: {
    color: THEME.textPrimary,
    fontSize: 16,
    fontWeight: "700",
  },
  aboutStatKey: {
    color: THEME.textSecondary,
    fontSize: 11,
    marginTop: 2,
  },
  aboutDetail: {
    flexDirection: "row",
    alignItems: "center",
    gap: 10,
    paddingVertical: 4,
  },
  aboutDetailText: {
    color: THEME.textPrimary,
    fontSize: 14,
  },
});
