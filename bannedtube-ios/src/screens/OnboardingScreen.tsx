import React, { useState } from "react";
import {
  View,
  Text,
  Image,
  TextInput,
  TouchableOpacity,
  StyleSheet,
  ScrollView,
  Dimensions,
} from "react-native";

const logoLarge = require("../../assets/logo-large.png");
import { SafeAreaView } from "react-native-safe-area-context";
import { Ionicons } from "@expo/vector-icons";
import { LinearGradient } from "expo-linear-gradient";
import * as Haptics from "expo-haptics";
import { useApp } from "../lib/AppContext";
import { THEME, channels } from "../lib/data";

const { width: SCREEN_WIDTH } = Dimensions.get("window");

interface OnboardingScreenProps {
  onComplete: () => void;
}

export default function OnboardingScreen({ onComplete }: OnboardingScreenProps) {
  const { setProfile, toggleSubscription } = useApp();
  const [step, setStep] = useState(0);
  const [name, setName] = useState("");
  const [selectedChannels, setSelectedChannels] = useState<Set<string>>(new Set());

  const featuredChannels = channels.slice(0, 8);

  function handleChannelToggle(channelId: string) {
    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
    setSelectedChannels((prev) => {
      const next = new Set(prev);
      if (next.has(channelId)) {
        next.delete(channelId);
      } else {
        next.add(channelId);
      }
      return next;
    });
  }

  async function handleFinish() {
    Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
    if (name.trim()) {
      await setProfile({
        displayName: name.trim(),
        initial: name.trim()[0].toUpperCase(),
        avatarColor: THEME.accent,
        createdAt: new Date().toISOString(),
      });
    }
    for (const channelId of selectedChannels) {
      await toggleSubscription(channelId);
    }
    onComplete();
  }

  function handleNext() {
    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium);
    setStep(step + 1);
  }

  return (
    <SafeAreaView style={styles.container} edges={["top", "bottom"]}>
      <LinearGradient
        colors={["#0f0f0f", "#1a0a0a", "#0f0f0f"]}
        style={StyleSheet.absoluteFill}
      />

      <View style={styles.header}>
        {step > 0 && (
          <TouchableOpacity
            onPress={() => {
              Haptics.selectionAsync();
              setStep(step - 1);
            }}
            accessibilityLabel="Go back"
          >
            <Ionicons name="arrow-back" size={24} color={THEME.textPrimary} />
          </TouchableOpacity>
        )}
        <Text style={styles.stepText}>Step {step + 1} of 3</Text>
      </View>

      <View style={styles.progressBar}>
        <View style={[styles.progressFill, { width: `${((step + 1) / 3) * 100}%` }]} />
      </View>

      {step === 0 && (
        <ScrollView contentContainerStyle={styles.stepContent} showsVerticalScrollIndicator={false}>
          <View style={styles.logoWrap}>
            <Image source={logoLarge} style={styles.logoIcon} resizeMode="contain" />
          </View>
          <Text style={styles.welcomeTitle}>Welcome to BannedTube</Text>
          <Text style={styles.tagline}>For the creators that were wrongfully banned.</Text>
          <Text style={styles.welcomeSubtitle}>
            The local-first video platform. No account needed — everything stays on your device.
          </Text>
          <Text style={styles.featureBullet}>• Watch, like, save, and subscribe</Text>
          <Text style={styles.featureBullet}>• Comment and reply to the community</Text>
          <Text style={styles.featureBullet}>• Clips, Trending, AI Studio, and more</Text>
          <Text style={styles.featureBullet}>• Zero data leaves your phone</Text>
          <TouchableOpacity style={styles.primaryBtn} onPress={handleNext}>
            <Text style={styles.primaryBtnText}>Get Started</Text>
          </TouchableOpacity>
        </ScrollView>
      )}

      {step === 1 && (
        <ScrollView contentContainerStyle={styles.stepContent} showsVerticalScrollIndicator={false}>
          <Text style={styles.stepTitle}>What should we call you?</Text>
          <Text style={styles.stepSubtitle}>
            Choose a display name. You can change this later in Settings.
          </Text>
          <View style={styles.inputWrap}>
            <Ionicons name="person-outline" size={20} color={THEME.textSecondary} />
            <TextInput
              style={styles.nameInput}
              placeholder="Your name"
              placeholderTextColor="#666"
              value={name}
              onChangeText={setName}
              maxLength={20}
              returnKeyType="done"
              accessibilityLabel="Display name input"
            />
          </View>
          <TouchableOpacity
            style={[styles.primaryBtn, !name.trim() && styles.btnDisabled]}
            onPress={handleNext}
            disabled={!name.trim()}
          >
            <Text style={styles.primaryBtnText}>Continue</Text>
          </TouchableOpacity>
        </ScrollView>
      )}

      {step === 2 && (
        <ScrollView contentContainerStyle={styles.stepContent} showsVerticalScrollIndicator={false}>
          <Text style={styles.stepTitle}>Pick channels to follow</Text>
          <Text style={styles.stepSubtitle}>
            Subscribe to channels you're interested in. You can always change these later.
          </Text>
          {featuredChannels.map((channel) => {
            const selected = selectedChannels.has(channel.id);
            return (
              <TouchableOpacity
                key={channel.id}
                style={[styles.channelCard, selected && styles.channelCardSelected]}
                onPress={() => handleChannelToggle(channel.id)}
                accessibilityRole="button"
                accessibilityLabel={`${selected ? "Unsubscribe from" : "Subscribe to"} ${channel.name}`}
              >
                <View style={[styles.channelAvatar, { backgroundColor: channel.avatarColor }]}>
                  <Text style={styles.channelInitial}>{channel.initial}</Text>
                </View>
                <View style={styles.channelInfo}>
                  <View style={styles.channelNameRow}>
                    <Text style={styles.channelName}>{channel.name}</Text>
                    {channel.verified && (
                      <Ionicons name="checkmark-circle" size={14} color={THEME.textSecondary} />
                    )}
                  </View>
                  <Text style={styles.channelSubs}>
                    {(channel.subscribers / 1000).toFixed(0)}K subscribers
                  </Text>
                </View>
                <View style={[styles.checkbox, selected && styles.checkboxSelected]}>
                  <Ionicons
                    name={selected ? "checkmark" : "add"}
                    size={18}
                    color={selected ? "#fff" : THEME.textSecondary}
                  />
                </View>
              </TouchableOpacity>
            );
          })}
          <TouchableOpacity style={styles.primaryBtn} onPress={handleFinish}>
            <Text style={styles.primaryBtnText}>
              {selectedChannels.size > 0
                ? `Finish (${selectedChannels.size} subscriptions)`
                : "Skip for now"}
            </Text>
          </TouchableOpacity>
        </ScrollView>
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
    paddingHorizontal: 16,
    paddingTop: 14,
    paddingBottom: 8,
    gap: 16,
  },
  stepText: {
    color: THEME.textSecondary,
    fontSize: 14,
    fontWeight: "500",
  },
  progressBar: {
    height: 3,
    backgroundColor: THEME.bgTertiary,
    marginHorizontal: 16,
    borderRadius: 2,
    marginBottom: 20,
  },
  progressFill: {
    height: 3,
    backgroundColor: THEME.accent,
    borderRadius: 2,
  },
  stepContent: {
    paddingHorizontal: 24,
    paddingBottom: 40,
    flexGrow: 1,
  },
  logoWrap: {
    alignItems: "center",
    marginBottom: 24,
    marginTop: 20,
  },
  logoIcon: {
    width: 80,
    height: 80,
    borderRadius: 24,
    justifyContent: "center",
    alignItems: "center",
  },
  welcomeTitle: {
    color: THEME.textPrimary,
    fontSize: 28,
    fontWeight: "800",
    textAlign: "center",
    marginBottom: 12,
  },
  tagline: {
    color: THEME.accent,
    fontSize: 16,
    fontWeight: "600",
    fontStyle: "italic",
    textAlign: "center",
    marginBottom: 12,
  },
  welcomeSubtitle: {
    color: THEME.textSecondary,
    fontSize: 16,
    textAlign: "center",
    lineHeight: 22,
    marginBottom: 28,
  },
  featureBullet: {
    color: THEME.textPrimary,
    fontSize: 15,
    marginBottom: 12,
    paddingLeft: 4,
  },
  stepTitle: {
    color: THEME.textPrimary,
    fontSize: 24,
    fontWeight: "700",
    marginBottom: 8,
  },
  stepSubtitle: {
    color: THEME.textSecondary,
    fontSize: 15,
    marginBottom: 24,
    lineHeight: 20,
  },
  inputWrap: {
    flexDirection: "row",
    alignItems: "center",
    backgroundColor: THEME.bgSecondary,
    borderRadius: 16,
    paddingHorizontal: 16,
    paddingVertical: 4,
    gap: 12,
    borderWidth: 1,
    borderColor: THEME.border,
    marginBottom: 24,
  },
  nameInput: {
    flex: 1,
    color: THEME.textPrimary,
    fontSize: 17,
    paddingVertical: 14,
  },
  primaryBtn: {
    backgroundColor: THEME.accent,
    paddingVertical: 16,
    borderRadius: 24,
    alignItems: "center",
    marginTop: 16,
  },
  primaryBtnText: {
    color: "#fff",
    fontSize: 17,
    fontWeight: "700",
  },
  btnDisabled: {
    opacity: 0.3,
  },
  channelCard: {
    flexDirection: "row",
    alignItems: "center",
    paddingVertical: 12,
    gap: 12,
  },
  channelCardSelected: {
    // Could add highlight
  },
  channelAvatar: {
    width: 48,
    height: 48,
    borderRadius: 24,
    justifyContent: "center",
    alignItems: "center",
  },
  channelInitial: {
    color: "#fff",
    fontSize: 20,
    fontWeight: "700",
  },
  channelInfo: {
    flex: 1,
  },
  channelNameRow: {
    flexDirection: "row",
    alignItems: "center",
    gap: 4,
  },
  channelName: {
    color: THEME.textPrimary,
    fontSize: 15,
    fontWeight: "600",
  },
  channelSubs: {
    color: THEME.textSecondary,
    fontSize: 13,
    marginTop: 2,
  },
  checkbox: {
    width: 32,
    height: 32,
    borderRadius: 16,
    backgroundColor: THEME.bgSecondary,
    justifyContent: "center",
    alignItems: "center",
    borderWidth: 1,
    borderColor: THEME.border,
  },
  checkboxSelected: {
    backgroundColor: THEME.accent,
    borderColor: THEME.accent,
  },
});
