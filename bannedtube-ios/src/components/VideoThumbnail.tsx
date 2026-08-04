import React from "react";
import { View, Text, StyleSheet } from "react-native";
import { LinearGradient } from "expo-linear-gradient";
import { Ionicons } from "@expo/vector-icons";
import { THEME } from "../lib/data";

interface VideoThumbnailProps {
  colors: [string, string];
  duration: string;
  title: string;
  height?: number;
}

export default function VideoThumbnail({
  colors,
  duration,
  title,
  height = 200,
}: VideoThumbnailProps) {
  return (
    <View style={[styles.container, { height }]}>
      <LinearGradient
        colors={[colors[0], colors[1]]}
        start={{ x: 0, y: 0 }}
        end={{ x: 1, y: 1 }}
        style={StyleSheet.absoluteFill}
      />

      {/* Top vignette mask */}
      <LinearGradient
        colors={["rgba(0,0,0,0.3)", "transparent"]}
        start={{ x: 0, y: 0 }}
        end={{ x: 0, y: 0.4 }}
        style={StyleSheet.absoluteFill}
      />

      {/* Bottom mask for title */}
      <LinearGradient
        colors={["transparent", "rgba(0,0,0,0.7)"]}
        start={{ x: 0, y: 0.5 }}
        end={{ x: 0, y: 1 }}
        style={StyleSheet.absoluteFill}
      />

      {/* Play icon with glow */}
      <View style={styles.playContainer}>
        <View style={styles.playGlow} />
        <View style={styles.playButton}>
          <Ionicons name="play" size={24} color="#fff" style={{ marginLeft: 3 }} />
        </View>
      </View>

      {/* Title at bottom with mask */}
      <View style={styles.titleBar}>
        <Text style={styles.titleText} numberOfLines={1}>
          {title}
        </Text>
      </View>

      {/* Duration badge */}
      <View style={styles.durationBadge}>
        <Text style={styles.durationText}>{duration}</Text>
      </View>

      {/* Corner mask accents */}
      <LinearGradient
        colors={["rgba(255,68,68,0.15)", "transparent"]}
        start={{ x: 0, y: 0 }}
        end={{ x: 0.3, y: 0.3 }}
        style={[StyleSheet.absoluteFill, { borderTopLeftRadius: 12 }]}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    borderRadius: 12,
    overflow: "hidden",
    justifyContent: "center",
    alignItems: "center",
  },
  playContainer: {
    position: "relative",
    marginBottom: 20,
  },
  playGlow: {
    position: "absolute",
    width: 60,
    height: 60,
    borderRadius: 30,
    backgroundColor: "rgba(255,68,68,0.25)",
    top: -6,
    left: -6,
  },
  playButton: {
    width: 48,
    height: 48,
    borderRadius: 24,
    backgroundColor: "rgba(255,255,255,0.15)",
    justifyContent: "center",
    alignItems: "center",
    borderWidth: 1.5,
    borderColor: "rgba(255,255,255,0.2)",
  },
  titleBar: {
    position: "absolute",
    bottom: 0,
    left: 0,
    right: 0,
    paddingHorizontal: 10,
    paddingBottom: 8,
    paddingTop: 20,
  },
  titleText: {
    color: "#fff",
    fontSize: 13,
    fontWeight: "600",
    textShadowColor: "rgba(0,0,0,0.8)",
    textShadowOffset: { width: 0, height: 1 },
    textShadowRadius: 4,
  },
  durationBadge: {
    position: "absolute",
    bottom: 8,
    right: 8,
    backgroundColor: "rgba(0,0,0,0.85)",
    paddingHorizontal: 5,
    paddingVertical: 2,
    borderRadius: 4,
  },
  durationText: {
    color: "#fff",
    fontSize: 11,
    fontWeight: "700",
    letterSpacing: 0.3,
  },
});
