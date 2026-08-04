import React from "react";
import { View, StyleSheet, type StyleProp, type ViewStyle } from "react-native";
import { BlurView } from "expo-blur";
import { LinearGradient } from "expo-linear-gradient";
import { THEME } from "../lib/data";

interface GlassCardProps {
  children: React.ReactNode;
  style?: StyleProp<ViewStyle>;
  intensity?: number;
  accentGlow?: boolean;
}

export default function GlassCard({
  children,
  style,
  intensity = 40,
  accentGlow = false,
}: GlassCardProps) {
  return (
    <View style={[styles.container, style]}>
      <BlurView intensity={intensity} tint="dark" style={StyleSheet.absoluteFill} />
      <LinearGradient
        colors={[
          "rgba(255,255,255,0.08)",
          "rgba(255,255,255,0.03)",
          "rgba(255,255,255,0.01)",
        ]}
        start={{ x: 0, y: 0 }}
        end={{ x: 1, y: 1 }}
        style={StyleSheet.absoluteFill}
      />
      {accentGlow && (
        <LinearGradient
          colors={[THEME.accentGlow, "transparent"]}
          start={{ x: 0, y: 0 }}
          end={{ x: 0.5, y: 0.5 }}
          style={[StyleSheet.absoluteFill, { opacity: 0.6 }]}
        />
      )}
      <View style={styles.content}>{children}</View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    borderRadius: 16,
    overflow: "hidden",
    borderWidth: 1,
    borderColor: THEME.glassBorder,
  },
  content: {
    padding: 16,
  },
});
