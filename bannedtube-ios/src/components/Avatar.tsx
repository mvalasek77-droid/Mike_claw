import React from "react";
import { View, Text, Image, ImageSourcePropType, StyleSheet } from "react-native";

interface AvatarProps {
  color: string;
  initial: string;
  size?: number;
  borderColor?: string;
  imageSource?: ImageSourcePropType;
}

export default function Avatar({
  color,
  initial,
  size = 36,
  borderColor,
  imageSource,
}: AvatarProps) {
  return (
    <View
      style={[
        styles.container,
        {
          width: size,
          height: size,
          borderRadius: size / 2,
          backgroundColor: imageSource ? "transparent" : color,
          borderWidth: borderColor ? 2 : 0,
          borderColor: borderColor || "transparent",
          overflow: "hidden",
        },
      ]}
      accessibilityRole="image"
      accessibilityLabel={`${initial} avatar`}
    >
      {imageSource ? (
        <Image
          source={imageSource}
          style={{ width: size, height: size }}
          resizeMode="cover"
        />
      ) : (
        <Text
          style={[styles.initial, { fontSize: size * 0.4 }]}
          numberOfLines={1}
          allowFontScaling={false}
        >
          {initial}
        </Text>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    justifyContent: "center",
    alignItems: "center",
    shadowColor: "#000",
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.2,
    shadowRadius: 4,
    elevation: 3,
  },
  initial: {
    color: "#fff",
    fontWeight: "700",
    letterSpacing: 0.5,
  },
});
