import React, { useState } from "react";
import {
  View,
  Text,
  TouchableOpacity,
  StyleSheet,
  ScrollView,
  Switch,
  Alert,
  Linking,
  Platform,
  TextInput,
} from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { Ionicons } from "@expo/vector-icons";
import * as Haptics from "expo-haptics";
import { useApp } from "../lib/AppContext";
import { THEME, formatCompact } from "../lib/data";
import { APP_VERSION } from "../lib/bugReports";

const PRIVACY_POLICY_URL = "https://bannedtube.app/privacy-policy.html";

async function openLink(url: string, label: string) {
  Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
  try {
    await Linking.openURL(url);
  } catch {
    Alert.alert(`Couldn't open ${label}`, url);
  }
}

interface YouScreenProps {
  onChannelPress: (channelId: string) => void;
  onBugReport: () => void;
  onNavigate: (tab: "library" | "subscriptions") => void;
}

export default function YouScreen({
  onBugReport,
  onNavigate,
}: YouScreenProps) {
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
  const [nameDraft, setNameDraft] = useState("");

  const stats = [
    { label: "Watched", value: formatCompact(watchHistory.length) },
    { label: "Saved", value: formatCompact(savedVideos.size) },
    { label: "Liked", value: formatCompact(likedVideos.size) },
    { label: "Following", value: formatCompact(subscriptions.size) },
  ];

  const menuItems: {
    icon: string;
    label: string;
    target: "library" | "subscriptions";
  }[] = [
    { icon: "time-outline", label: "History", target: "library" },
    { icon: "bookmark-outline", label: "Saved", target: "library" },
    { icon: "thumbs-up-outline", label: "Liked", target: "library" },
    { icon: "people-outline", label: "Following", target: "subscriptions" },
  ];

  // Only settings the app actually honours are shown. Push notifications and a
  // light theme are not implemented, so toggles for them would do nothing.
  const settingsItems = [
    {
      icon: "volume-mute-outline",
      label: "Start videos muted",
      key: "autoplayMuted" as const,
    },
    {
      icon: "play-circle-outline",
      label: "Autoplay next video",
      key: "autoplayNext" as const,
    },
  ];

  const saveName = (text: string) => {
    const trimmed = text.trim();
    if (!trimmed) return;
    setProfile({
      displayName: trimmed,
      initial: trimmed[0].toUpperCase(),
      avatarColor: profile?.avatarColor || THEME.accent,
      createdAt: profile?.createdAt || new Date().toISOString(),
    });
    Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
  };

  // Alert.prompt is iOS-only, so Android gets an inline editor instead.
  const handleNameEdit = () => {
    if (Platform.OS !== "ios") {
      setNameDraft(profile?.displayName || "");
      setEditingName(true);
      return;
    }
    Alert.prompt(
      "Edit display name",
      "Enter your display name",
      [
        { text: "Cancel", style: "cancel" },
        { text: "Save", onPress: (text?: string) => saveName(text ?? "") },
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
            {editingName ? (
              <View style={styles.nameEditRow}>
                <TextInput
                  style={styles.nameInput}
                  value={nameDraft}
                  onChangeText={setNameDraft}
                  placeholder="Display name"
                  placeholderTextColor={THEME.textSecondary}
                  autoFocus
                  maxLength={40}
                  returnKeyType="done"
                  onSubmitEditing={() => {
                    saveName(nameDraft);
                    setEditingName(false);
                  }}
                  accessibilityLabel="Display name"
                />
                <TouchableOpacity
                  onPress={() => {
                    saveName(nameDraft);
                    setEditingName(false);
                  }}
                  style={styles.editBtn}
                  accessibilityRole="button"
                  accessibilityLabel="Save display name"
                >
                  <Text style={styles.editBtnText}>Save</Text>
                </TouchableOpacity>
              </View>
            ) : (
              <TouchableOpacity
                style={styles.editBtn}
                onPress={handleNameEdit}
                accessibilityRole="button"
                accessibilityLabel="Edit profile"
              >
                <Text style={styles.editBtnText}>Edit profile</Text>
              </TouchableOpacity>
            )}
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
              onPress={() => {
                Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
                onNavigate(item.target);
              }}
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

        {/* Support */}
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Support</Text>
          <TouchableOpacity
            style={styles.menuItem}
            onPress={() => {
              Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
              onBugReport();
            }}
            accessibilityRole="button"
            accessibilityLabel="Report a bug"
          >
            <Ionicons name="bug-outline" size={22} color={THEME.textSecondary} />
            <Text style={styles.menuItemText}>Report a bug</Text>
            <Ionicons name="chevron-forward" size={18} color={THEME.bgTertiary} />
          </TouchableOpacity>
          <TouchableOpacity
            style={styles.menuItem}
            onPress={() => openLink(PRIVACY_POLICY_URL, "Privacy Policy")}
            accessibilityRole="button"
            accessibilityLabel="Privacy Policy"
          >
            <Ionicons name="shield-outline" size={22} color={THEME.textSecondary} />
            <Text style={styles.menuItemText}>Privacy Policy</Text>
            <Ionicons name="open-outline" size={16} color={THEME.bgTertiary} />
          </TouchableOpacity>
        </View>

        <View style={styles.footer}>
          <Text style={styles.versionText}>BannedTube v{APP_VERSION}</Text>
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
  nameEditRow: {
    flexDirection: "row",
    alignItems: "center",
    gap: 8,
    marginTop: 6,
  },
  nameInput: {
    flex: 1,
    backgroundColor: THEME.bgSecondary,
    borderWidth: 1,
    borderColor: THEME.border,
    borderRadius: 8,
    paddingHorizontal: 10,
    paddingVertical: 6,
    color: THEME.textPrimary,
    fontSize: 14,
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
