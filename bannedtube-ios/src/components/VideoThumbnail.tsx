import React from "react";
import { View, Text, Image, ImageSourcePropType, StyleSheet } from "react-native";
import { LinearGradient } from "expo-linear-gradient";
import { Ionicons } from "@expo/vector-icons";
import { THEME } from "../lib/data";

interface VideoThumbnailProps {
  colors: [string, string];
  duration: string;
  title: string;
  height?: number;
  progressPercent?: number;
  saved?: boolean;
  imageSource?: ImageSourcePropType;
}

export default function VideoThumbnail({
  colors,
  duration,
  title,
  height = 200,
  progressPercent = 0,
  saved = false,
  imageSource,
}: VideoThumbnailProps) {
  return (
    <View
      style={[styles.container, { height }]}
      accessibilityRole="image"
      accessibilityLabel={`Thumbnail for ${title}`}
    >
      {imageSource ? (
        <Image
          source={imageSource}
          style={StyleSheet.absoluteFill}
          resizeMode="cover"
        />
      ) : (
        <>
          <LinearGradient
            colors={[colors[0], colors[1]]}
            start={{ x: 0, y: 0 }}
            end={{ x: 1, y: 1 }}
            style={StyleSheet.absoluteFill}
          />

          <LinearGradient
            colors={["rgba(0,0,0,0.35)", "transparent"]}
            start={{ x: 0, y: 0 }}
            end={{ x: 0, y: 0.4 }}
            style={StyleSheet.absoluteFill}
          />

          <LinearGradient
            colors={["transparent", "rgba(0,0,0,0.75)"]}
            start={{ x: 0, y: 0.5 }}
            end={{ x: 0, y: 1 }}
            style={StyleSheet.absoluteFill}
          />

          <View style={styles.playContainer}>
            <View style={styles.playGlow} />
            <View style={styles.playButton}>
              <Ionicons
                name="play"
                size={24}
                color="#fff"
                style={{ marginLeft: 3 }}
              />
            </View>
          </View>

          <View style={styles.titleBar}>
            <Text style={styles.titleText} numberOfLines={1}>
              {title}
            </Text>
          </View>

          <LinearGradient
            colors={["rgba(255,68,68,0.12)", "transparent"]}
            start={{ x: 0, y: 0 }}
            end={{ x: 0.35, y: 0.35 }}
            style={[StyleSheet.absoluteFill, { borderTopLeftRadius: 12 }]}
          />
          <LinearGradient
            colors={["rgba(255,68,68,0.06)", "transparent"]}
            start={{ x: 1, y: 1 }}
            end={{ x: 0.7, y: 0.7 }}
            style={[StyleSheet.absoluteFill, { borderBottomRightRadius: 12 }]}
          />
        </>
      )}

      {saved && (
        <View style={styles.savedBadge}>
          <Ionicons name="bookmark" size={12} color="#fff" />
        </View>
      )}

      <View
        style={styles.durationBadge}
        accessibilityLabel={`Duration: ${duration}`}
      >
        <Text style={styles.durationText}>{duration}</Text>
      </View>

      {progressPercent > 0 && (
        <View style={styles.progressTrack}>
          <View
            style={[styles.progressFill, { width: `${Math.min(progressPercent, 100)}%` }]}
          />
        </View>
      )}
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
    width: 64,
    height: 64,
    borderRadius: 32,
    backgroundColor: "rgba(255,68,68,0.2)",
    top: -8,
    left: -8,
  },
  playButton: {
    width: 48,
    height: 48,
    borderRadius: 24,
    backgroundColor: "rgba(255,255,255,0.12)",
    justifyContent: "center",
    alignItems: "center",
    borderWidth: 1.5,
    borderColor: "rgba(255,255,255,0.18)",
  },
  titleBar: {
    position: "absolute",
    bottom: 0,
    left: 0,
    right: 0,
    paddingHorizontal: 10,
    paddingBottom: 8,
    paddingTop: 24,
  },
  titleText: {
    color: "#fff",
    fontSize: 13,
    fontWeight: "600",
    textShadowColor: "rgba(0,0,0,0.9)",
    textShadowOffset: { width: 0, height: 1 },
    textShadowRadius: 4,
  },
  savedBadge: {
    position: "absolute",
    top: 8,
    right: 8,
    backgroundColor: "rgba(255,68,68,0.9)",
    width: 22,
    height: 22,
    borderRadius: 6,
    justifyContent: "center",
    alignItems: "center",
  },
  durationBadge: {
    position: "absolute",
    bottom: 8,
    right: 8,
    backgroundColor: "rgba(0,0,0,0.85)",
    paddingHorizontal: 6,
    paddingVertical: 2,
    borderRadius: 4,
  },
  durationText: {
    color: "#fff",
    fontSize: 11,
    fontWeight: "700",
    letterSpacing: 0.3,
  },
  progressTrack: {
    position: "absolute",
    bottom: 0,
    left: 0,
    right: 0,
    height: 3,
    backgroundColor: "rgba(255,255,255,0.2)",
  },
  progressFill: {
    height: 3,
    backgroundColor: THEME.accent,
  },
});
