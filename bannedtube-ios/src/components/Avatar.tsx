import React from "react";
import { View, Text, StyleSheet } from "react-native";

interface AvatarProps {
  color: string;
  initial: string;
  size?: number;
  borderColor?: string;
}

export default function Avatar({
  color,
  initial,
  size = 36,
  borderColor,
}: AvatarProps) {
  return (
    <View
      style={[
        styles.container,
        {
          width: size,
          height: size,
          borderRadius: size / 2,
          backgroundColor: color,
          borderWidth: borderColor ? 2 : 0,
          borderColor: borderColor || "transparent",
        },
      ]}
    >
      <Text
        style={[styles.initial, { fontSize: size * 0.42 }]}
        numberOfLines={1}
      >
        {initial}
      </Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    justifyContent: "center",
    alignItems: "center",
  },
  initial: {
    color: "#fff",
    fontWeight: "700",
  },
});
