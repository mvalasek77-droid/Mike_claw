import React from "react";
import { View, Text, Image, TouchableOpacity, StyleSheet } from "react-native";
import { LinearGradient } from "expo-linear-gradient";
import { BlurView } from "expo-blur";
import { Ionicons } from "@expo/vector-icons";
import { THEME } from "../lib/data";

const logoIcon = require("../../assets/logo-icon.png");

interface HeaderProps {
  onSearch?: () => void;
  onNotification?: () => void;
}

export default function Header({ onSearch, onNotification }: HeaderProps) {
  return (
    <View style={styles.wrapper}>
      <BlurView intensity={30} tint="dark" style={StyleSheet.absoluteFill} />
      <LinearGradient
        colors={[THEME.bgPrimary, "rgba(15,15,15,0.92)"]}
        style={StyleSheet.absoluteFill}
      />
      <View style={styles.container}>
        <View
          style={styles.logoRow}
          accessibilityRole="header"
          accessibilityLabel="BannedTube"
        >
          <Image source={logoIcon} style={styles.logoIcon} resizeMode="contain" />
          <Text style={styles.logoText} allowFontScaling={false}>
            Banned<Text style={styles.logoAccent}>Tube</Text>
          </Text>
        </View>

        <View style={styles.actions}>
          <TouchableOpacity
            style={styles.actionBtn}
            onPress={onSearch}
            activeOpacity={0.6}
            accessibilityRole="button"
            accessibilityLabel="Search"
          >
            <Ionicons name="search" size={22} color={THEME.textPrimary} />
          </TouchableOpacity>
          <TouchableOpacity
            style={styles.actionBtn}
            onPress={onNotification}
            activeOpacity={0.6}
            accessibilityRole="button"
            accessibilityLabel="Notifications"
          >
            <Ionicons
              name="notifications-outline"
              size={22}
              color={THEME.textPrimary}
            />
            <View style={styles.notifDot} />
          </TouchableOpacity>
          <View
            style={styles.profileBtn}
            accessibilityRole="image"
            accessibilityLabel="Profile"
          >
            <Ionicons name="person" size={14} color="#fff" />
          </View>
        </View>
      </View>
      <LinearGradient
        colors={["transparent", "rgba(255,68,68,0.08)", "transparent"]}
        start={{ x: 0, y: 0 }}
        end={{ x: 1, y: 0 }}
        style={styles.borderGradient}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  wrapper: {
    position: "relative",
    overflow: "hidden",
  },
  container: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
    paddingHorizontal: 16,
    paddingTop: 8,
    paddingBottom: 10,
  },
  logoRow: {
    flexDirection: "row",
    alignItems: "center",
    gap: 6,
  },
  logoIcon: {
    width: 30,
    height: 30,
    borderRadius: 8,
  },
  logoText: {
    fontSize: 18,
    fontWeight: "800",
    color: THEME.textPrimary,
    letterSpacing: -0.3,
  },
  logoAccent: {
    color: THEME.accent,
  },
  actions: {
    flexDirection: "row",
    alignItems: "center",
    gap: 6,
  },
  actionBtn: {
    width: 38,
    height: 38,
    borderRadius: 19,
    justifyContent: "center",
    alignItems: "center",
    position: "relative",
  },
  notifDot: {
    position: "absolute",
    top: 8,
    right: 8,
    width: 6,
    height: 6,
    borderRadius: 3,
    backgroundColor: THEME.accent,
  },
  profileBtn: {
    width: 30,
    height: 30,
    borderRadius: 15,
    backgroundColor: "#805ad5",
    justifyContent: "center",
    alignItems: "center",
    marginLeft: 4,
  },
  borderGradient: {
    height: 1,
  },
});
