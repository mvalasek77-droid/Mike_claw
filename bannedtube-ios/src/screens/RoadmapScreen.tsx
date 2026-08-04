import React, { useRef, useEffect } from "react";
import {
  View,
  Text,
  ScrollView,
  StyleSheet,
  Animated,
} from "react-native";
import { LinearGradient } from "expo-linear-gradient";
import { Ionicons } from "@expo/vector-icons";
import GlassCard from "../components/GlassCard";
import { THEME } from "../lib/data";

interface RoadmapPhase {
  phase: string;
  title: string;
  status: "shipped" | "in-progress" | "planned";
  items: { feature: string; description: string; icon: string }[];
}

const ROADMAP: RoadmapPhase[] = [
  {
    phase: "1.0",
    title: "Foundation",
    status: "shipped",
    items: [
      {
        feature: "Video Feed",
        description: "Infinite scroll feed with category filtering and grid/list layouts",
        icon: "videocam",
      },
      {
        feature: "Channel Profiles",
        description: "Full channel pages with banner, avatar glow, tabs, and video grid",
        icon: "person-circle",
      },
      {
        feature: "Watch Experience",
        description: "Immersive player with gradient backgrounds, threaded comments, related videos",
        icon: "play-circle",
      },
      {
        feature: "Search",
        description: "Full-text search across titles, channels, tags, and categories",
        icon: "search",
      },
      {
        feature: "Native Navigation",
        description: "Bottom tab bar with haptic feedback, overlay-based screen stack",
        icon: "navigate",
      },
    ],
  },
  {
    phase: "1.5",
    title: "AI & Creator Tools",
    status: "shipped",
    items: [
      {
        feature: "AI Studio",
        description: "AI-powered title generator with confidence scoring and reasoning",
        icon: "sparkles",
      },
      {
        feature: "Trend Analyzer",
        description: "Real-time trending topic tracking with growth metrics and content angles",
        icon: "analytics",
      },
      {
        feature: "Creator Insights",
        description: "AI-powered analytics dashboard with personalized recommendations",
        icon: "bar-chart",
      },
      {
        feature: "Glassmorphism UI",
        description: "iOS 26 Liquid Glass design language with blur effects and accent glows",
        icon: "color-palette",
      },
    ],
  },
  {
    phase: "2.0",
    title: "iOS 26 Liquid Glass",
    status: "in-progress",
    items: [
      {
        feature: "Fluid Glass Navigation",
        description: "Depth-aware tab bar and headers with real-time blur and specular highlights",
        icon: "layers",
      },
      {
        feature: "Adaptive Haptics",
        description: "Context-aware haptic patterns: scroll resistance, button depths, gesture completion",
        icon: "hand-left",
      },
      {
        feature: "Depth Effects",
        description: "Parallax thumbnails, z-axis card elevation on scroll, 3D avatar tilt",
        icon: "cube",
      },
      {
        feature: "Dynamic Island Integration",
        description: "Live activity for video playback progress and channel notifications",
        icon: "phone-portrait",
      },
    ],
  },
  {
    phase: "3.0",
    title: "AI Content Engine",
    status: "planned",
    items: [
      {
        feature: "AI Thumbnail Generator",
        description: "Generate thumbnail concepts from video title using on-device diffusion models",
        icon: "image",
      },
      {
        feature: "Script Writer",
        description: "AI-assisted script drafting with tone matching and audience analysis",
        icon: "document-text",
      },
      {
        feature: "Smart Scheduling",
        description: "ML-predicted optimal upload times based on audience behavior patterns",
        icon: "calendar",
      },
      {
        feature: "Auto Chapters",
        description: "AI-generated chapter markers and timestamps from video transcripts",
        icon: "list",
      },
      {
        feature: "Voice Cloning Studio",
        description: "Clone your voice for narration, translations, and accessibility overlays",
        icon: "mic",
      },
    ],
  },
  {
    phase: "4.0",
    title: "Social & Monetization",
    status: "planned",
    items: [
      {
        feature: "Creator Tipping",
        description: "Direct peer-to-peer creator support with animated tip overlays",
        icon: "cash",
      },
      {
        feature: "Community Posts",
        description: "Rich media community tab with polls, images, and threaded discussions",
        icon: "chatbubbles",
      },
      {
        feature: "Collaborative Playlists",
        description: "Shared playlists with real-time co-editing and voting",
        icon: "musical-notes",
      },
      {
        feature: "Picture-in-Picture",
        description: "Native PiP with SwiftUI overlay, resize gestures, and snap-to-corner",
        icon: "resize",
      },
    ],
  },
];

function StatusBadge({ status }: { status: RoadmapPhase["status"] }) {
  const config = {
    shipped: { label: "Shipped", color: THEME.success, icon: "checkmark-circle" },
    "in-progress": { label: "In Progress", color: THEME.warning, icon: "build" },
    planned: { label: "Planned", color: THEME.info, icon: "time" },
  }[status];

  return (
    <View style={[badgeStyles.container, { backgroundColor: `${config.color}15` }]}>
      <Ionicons name={config.icon as any} size={12} color={config.color} />
      <Text style={[badgeStyles.text, { color: config.color }]}>
        {config.label}
      </Text>
    </View>
  );
}

const badgeStyles = StyleSheet.create({
  container: {
    flexDirection: "row",
    alignItems: "center",
    gap: 4,
    paddingHorizontal: 10,
    paddingVertical: 4,
    borderRadius: 8,
  },
  text: {
    fontSize: 11,
    fontWeight: "600",
  },
});

function PhaseCard({ phase, index }: { phase: RoadmapPhase; index: number }) {
  const fadeAnim = useRef(new Animated.Value(0)).current;
  const slideAnim = useRef(new Animated.Value(20)).current;

  useEffect(() => {
    Animated.parallel([
      Animated.timing(fadeAnim, {
        toValue: 1,
        duration: 400,
        delay: index * 100,
        useNativeDriver: true,
      }),
      Animated.timing(slideAnim, {
        toValue: 0,
        duration: 400,
        delay: index * 100,
        useNativeDriver: true,
      }),
    ]).start();
  }, []);

  return (
    <Animated.View
      style={{
        opacity: fadeAnim,
        transform: [{ translateY: slideAnim }],
      }}
    >
      <GlassCard
        style={styles.phaseCard}
        accentGlow={phase.status === "in-progress"}
      >
        <View style={styles.phaseHeader}>
          <View>
            <Text style={styles.phaseLabel}>Phase {phase.phase}</Text>
            <Text style={styles.phaseTitle}>{phase.title}</Text>
          </View>
          <StatusBadge status={phase.status} />
        </View>
        {phase.items.map((item, i) => (
          <View
            key={item.feature}
            style={[
              styles.featureRow,
              i < phase.items.length - 1 && styles.featureRowBorder,
            ]}
          >
            <View style={styles.featureIcon}>
              <Ionicons
                name={item.icon as any}
                size={18}
                color={
                  phase.status === "shipped"
                    ? THEME.success
                    : phase.status === "in-progress"
                      ? THEME.warning
                      : THEME.info
                }
              />
            </View>
            <View style={{ flex: 1 }}>
              <Text style={styles.featureName}>{item.feature}</Text>
              <Text style={styles.featureDesc}>{item.description}</Text>
            </View>
          </View>
        ))}
      </GlassCard>
    </Animated.View>
  );
}

export default function RoadmapScreen() {
  return (
    <View style={styles.container}>
      <View style={styles.header}>
        <LinearGradient
          colors={["rgba(96,165,250,0.06)", "transparent"]}
          start={{ x: 0, y: 0 }}
          end={{ x: 1, y: 1 }}
          style={StyleSheet.absoluteFill}
        />
        <View style={styles.headerContent}>
          <View style={styles.headerIcon}>
            <Ionicons name="map" size={18} color="#fff" />
          </View>
          <View>
            <Text style={styles.headerTitle} accessibilityRole="header">
              Feature Roadmap
            </Text>
            <Text style={styles.headerSubtitle}>
              BannedTube iOS Development Plan
            </Text>
          </View>
        </View>
      </View>

      <ScrollView
        showsVerticalScrollIndicator={false}
        contentContainerStyle={styles.scrollContent}
      >
        <View style={styles.timelineConnector}>
          <LinearGradient
            colors={[THEME.success, THEME.warning, THEME.info, THEME.info]}
            style={styles.timelineLine}
          />
        </View>

        {ROADMAP.map((phase, i) => (
          <View key={phase.phase} style={styles.phaseRow}>
            <View style={styles.timelineDot}>
              <View
                style={[
                  styles.dot,
                  {
                    backgroundColor:
                      phase.status === "shipped"
                        ? THEME.success
                        : phase.status === "in-progress"
                          ? THEME.warning
                          : THEME.info,
                  },
                ]}
              />
            </View>
            <View style={{ flex: 1 }}>
              <PhaseCard phase={phase} index={i} />
            </View>
          </View>
        ))}

        <View style={{ height: 120 }} />
      </ScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: THEME.bgPrimary,
  },
  header: {
    overflow: "hidden",
    borderBottomWidth: 1,
    borderBottomColor: THEME.border,
  },
  headerContent: {
    flexDirection: "row",
    alignItems: "center",
    gap: 12,
    paddingHorizontal: 16,
    paddingVertical: 14,
  },
  headerIcon: {
    width: 36,
    height: 36,
    borderRadius: 12,
    backgroundColor: THEME.info,
    justifyContent: "center",
    alignItems: "center",
  },
  headerTitle: {
    color: THEME.textPrimary,
    fontSize: 20,
    fontWeight: "700",
  },
  headerSubtitle: {
    color: THEME.textSecondary,
    fontSize: 12,
    marginTop: 1,
  },
  scrollContent: {
    paddingHorizontal: 16,
    paddingTop: 20,
  },
  timelineConnector: {
    position: "absolute",
    left: 28,
    top: 20,
    bottom: 120,
    width: 2,
  },
  timelineLine: {
    flex: 1,
    width: 2,
    borderRadius: 1,
  },
  phaseRow: {
    flexDirection: "row",
    marginBottom: 16,
  },
  timelineDot: {
    width: 28,
    alignItems: "center",
    paddingTop: 20,
  },
  dot: {
    width: 10,
    height: 10,
    borderRadius: 5,
    borderWidth: 2,
    borderColor: THEME.bgPrimary,
  },
  phaseCard: {
    marginLeft: 8,
  },
  phaseHeader: {
    flexDirection: "row",
    justifyContent: "space-between",
    alignItems: "flex-start",
    marginBottom: 14,
  },
  phaseLabel: {
    color: THEME.textSecondary,
    fontSize: 11,
    fontWeight: "600",
    textTransform: "uppercase",
    letterSpacing: 1,
  },
  phaseTitle: {
    color: THEME.textPrimary,
    fontSize: 18,
    fontWeight: "700",
    marginTop: 2,
  },
  featureRow: {
    flexDirection: "row",
    gap: 10,
    paddingVertical: 10,
  },
  featureRowBorder: {
    borderBottomWidth: 1,
    borderBottomColor: "rgba(255,255,255,0.04)",
  },
  featureIcon: {
    width: 32,
    height: 32,
    borderRadius: 10,
    backgroundColor: "rgba(255,255,255,0.04)",
    justifyContent: "center",
    alignItems: "center",
    marginTop: 2,
  },
  featureName: {
    color: THEME.textPrimary,
    fontSize: 14,
    fontWeight: "600",
  },
  featureDesc: {
    color: THEME.textSecondary,
    fontSize: 12,
    lineHeight: 17,
    marginTop: 2,
  },
});
