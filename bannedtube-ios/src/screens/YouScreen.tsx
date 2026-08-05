import React, { useState } from "react";
import {
  View,
  Text,
  TouchableOpacity,
  StyleSheet,
  ScrollView,
  Switch,
  Alert,
} from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { Ionicons } from "@expo/vector-icons";
import * as Haptics from "expo-haptics";
import { useApp } from "../lib/AppContext";
import { THEME, formatCompact } from "../lib/data";

interface YouScreenProps {
  onChannelPress: (channelId: string) => void;
}

export default function YouScreen({ onChannelPress }: YouScreenProps) {
  const {
    profile,
    setProfile,
    watchHistory,
    savedVideos,
    likedVideos,
    subscriptions,
    notifications,
    setNotifications,
  } = useApp();

  const [editingName, setEditingName] = useState(false);

  const stats = [
    { label: "Videos watched", value: formatCompact(watchHistory.length) },
    { label: "Saved", value: formatCompact(savedVideos.size) },
    { label: "Liked", value: formatCompact(likedVideos.size) },
    { label: "Subscriptions", value: formatCompact(subscriptions.size) },
  ];

  const menuItems = [
    { icon: "time-outline", label: "History", screen: "library" },
    { icon: "bookmark-outline", label: "Saved", screen: "library" },
    { icon: "thumbs-up-outline", label: "Liked videos", screen: "library" },
    { icon: "download-outline", label: "Downloads", screen: "downloads" },
    { icon: "people-outline", label: "Subscriptions", screen: "subs" },
  ];

  const settingsItems = [
    { icon: "notifications-outline", label: "Notifications", toggle: true, key: "push" as const },
    { icon: "moon-outline", label: "Dark mode", toggle: true, key: "darkMode" as const },
    { icon: "volume-mute-outline", label: "Autoplay muted", toggle: true, key: "autoplayMuted" as const },
    { icon: "play-circle-outline", label: "Autoplay next", toggle: true, key: "autoplayNext" as const },
  ];

  const handleNameEdit = () => {
    Alert.prompt(
      "Edit display name",
      "Enter your display name",
      [
        { text: "Cancel", style: "cancel" },
        {
          text: "Save",
          onPress: (text?: string) => {
            if (text && text.trim()) {
              setProfile({
                displayName: text.trim(),
                initial: text.trim()[0].toUpperCase(),
                avatarColor: profile?.avatarColor || "#ff4444",
                createdAt: profile?.createdAt || new Date().toISOString(),
              });
              Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
            }
          },
        },
      ],
      "plain-text",
      profile?.displayName || ""
    );
  };

  return (
    <SafeAreaView style={styles.container} edges={["top"]}>
      <ScrollView showsVerticalScrollIndicator={false}>
        {/* Profile header */}
        <View style={styles.profileHeader}>
          <View style={[styles.avatar, { backgroundColor: profile?.avatarColor || THEME.accent }]}>
            <Text style={styles.avatarInitial}>{profile?.initial || "U"}</Text>
          </View>
          <View style={styles.profileInfo}>
            <Text style={styles.profileName}>{profile?.displayName || "Your Name"}</Text>
            <Text style={styles.profileHandle}>@{profile?.displayName?.toLowerCase().replace(/\s+/g, "") || "user"}</Text>
            <TouchableOpacity style={styles.editBtn} onPress={handleNameEdit}>
              <Text style={styles.editBtnText}>Edit profile</Text>
            </TouchableOpacity>
          </View>
        </View>

        {/* Stats row */}
        <View style={styles.statsRow}>
          {stats.map((stat, i) => (
            <View key={i} style={styles.statItem}>
              <Text style={styles.statValue}>{stat.value}</Text>
              <Text style={styles.statLabel}>{stat.label}</Text>
            </View>
          ))}
        </View>

        {/* Quick actions */}
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Quick actions</Text>
          {menuItems.map((item, i) => (
            <TouchableOpacity
              key={i}
              style={styles.menuItem}
              onPress={() => Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light)}
              accessibilityRole="button"
              accessibilityLabel={item.label}
            >
              <Ionicons name={item.icon as any} size={22} color={THEME.textSecondary} />
              <Text style={styles.menuItemText}>{item.label}</Text>
              <Ionicons name="chevron-forward" size={18} color={THEME.bgTertiary} />
            </TouchableOpacity>
          ))}
        </View>

        {/* Settings */}
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Settings</Text>
          {settingsItems.map((item, i) => (
            <View key={i} style={styles.menuItem}>
              <Ionicons name={item.icon as any} size={22} color={THEME.textSecondary} />
              <Text style={styles.menuItemText}>{item.label}</Text>
              <Switch
                value={notifications[item.key]}
                onValueChange={(val) => {
                  setNotifications({ ...notifications, [item.key]: val });
                  Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
                }}
                trackColor={{ false: THEME.bgTertiary, true: THEME.accent }}
                thumbColor="#fff"
              />
            </View>
          ))}
        </View>

        {/* About */}
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>About</Text>
          <TouchableOpacity style={styles.menuItem} accessibilityLabel="Privacy Policy">
            <Ionicons name="shield-outline" size={22} color={THEME.textSecondary} />
            <Text style={styles.menuItemText}>Privacy Policy</Text>
            <Ionicons name="chevron-forward" size={18} color={THEME.bgTertiary} />
          </TouchableOpacity>
          <TouchableOpacity style={styles.menuItem} accessibilityLabel="Terms of Service">
            <Ionicons name="document-text-outline" size={22} color={THEME.textSecondary} />
            <Text style={styles.menuItemText}>Terms of Service</Text>
            <Ionicons name="chevron-forward" size={18} color={THEME.bgTertiary} />
          </TouchableOpacity>
          <TouchableOpacity style={styles.menuItem} accessibilityLabel="Help and feedback">
            <Ionicons name="help-circle-outline" size={22} color={THEME.textSecondary} />
            <Text style={styles.menuItemText}>Help & Feedback</Text>
            <Ionicons name="chevron-forward" size={18} color={THEME.bgTertiary} />
          </TouchableOpacity>
        </View>

        <View style={styles.footer}>
          <Text style={styles.versionText}>BannedTube v1.0.0</Text>
          <Text style={styles.versionSubtext}>Local-first · No account needed</Text>
        </View>
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: THEME.bgPrimary,
  },
  profileHeader: {
    flexDirection: "row",
    alignItems: "center",
    paddingHorizontal: 16,
    paddingTop: 20,
    paddingBottom: 16,
    gap: 16,
  },
  avatar: {
    width: 72,
    height: 72,
    borderRadius: 36,
    justifyContent: "center",
    alignItems: "center",
  },
  avatarInitial: {
    color: "#fff",
    fontSize: 30,
    fontWeight: "700",
  },
  profileInfo: {
    flex: 1,
    gap: 4,
  },
  profileName: {
    color: THEME.textPrimary,
    fontSize: 20,
    fontWeight: "700",
  },
  profileHandle: {
    color: THEME.textSecondary,
    fontSize: 14,
  },
  editBtn: {
    marginTop: 6,
    backgroundColor: THEME.bgSecondary,
    paddingHorizontal: 14,
    paddingVertical: 6,
    borderRadius: 20,
    alignSelf: "flex-start",
    borderWidth: 1,
    borderColor: THEME.border,
  },
  editBtnText: {
    color: THEME.textPrimary,
    fontSize: 13,
    fontWeight: "600",
  },
  statsRow: {
    flexDirection: "row",
    paddingHorizontal: 16,
    paddingVertical: 14,
    justifyContent: "space-between",
  },
  statItem: {
    alignItems: "center",
    flex: 1,
  },
  statValue: {
    color: THEME.textPrimary,
    fontSize: 18,
    fontWeight: "700",
  },
  statLabel: {
    color: THEME.textSecondary,
    fontSize: 11,
    marginTop: 2,
  },
  section: {
    marginTop: 12,
    paddingHorizontal: 16,
  },
  sectionTitle: {
    color: THEME.textSecondary,
    fontSize: 13,
    fontWeight: "600",
    textTransform: "uppercase",
    letterSpacing: 0.5,
    marginBottom: 8,
  },
  menuItem: {
    flexDirection: "row",
    alignItems: "center",
    paddingVertical: 14,
    gap: 14,
  },
  menuItemText: {
    color: THEME.textPrimary,
    fontSize: 15,
    flex: 1,
  },
  footer: {
    alignItems: "center",
    paddingVertical: 32,
    gap: 4,
  },
  versionText: {
    color: THEME.textSecondary,
    fontSize: 13,
    fontWeight: "600",
  },
  versionSubtext: {
    color: THEME.bgTertiary,
    fontSize: 12,
  },
});
