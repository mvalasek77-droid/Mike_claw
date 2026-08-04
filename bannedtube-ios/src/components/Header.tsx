import React from "react";
import { View, Text, TouchableOpacity, StyleSheet } from "react-native";
import { LinearGradient } from "expo-linear-gradient";
import { Ionicons } from "@expo/vector-icons";
import { THEME } from "../lib/data";

interface HeaderProps {
  onSearch?: () => void;
  onNotification?: () => void;
}

export default function Header({ onSearch, onNotification }: HeaderProps) {
  return (
    <View style={styles.wrapper}>
      {/* Frosted glass mask effect */}
      <LinearGradient
        colors={[THEME.bgPrimary, "rgba(15,15,15,0.95)"]}
        style={StyleSheet.absoluteFill}
      />
      <View style={styles.container}>
        <View style={styles.logoRow}>
          <View style={styles.logoIcon}>
            <Ionicons name="flame" size={18} color="#fff" />
          </View>
          <Text style={styles.logoText}>
            Banned<Text style={styles.logoAccent}>Tube</Text>
          </Text>
        </View>

        <View style={styles.actions}>
          <TouchableOpacity
            style={styles.actionBtn}
            onPress={onSearch}
            activeOpacity={0.6}
          >
            <Ionicons name="search" size={22} color={THEME.textPrimary} />
          </TouchableOpacity>
          <TouchableOpacity
            style={styles.actionBtn}
            onPress={onNotification}
            activeOpacity={0.6}
          >
            <Ionicons
              name="notifications-outline"
              size={22}
              color={THEME.textPrimary}
            />
            <View style={styles.notifDot} />
          </TouchableOpacity>
          <View style={styles.profileBtn}>
            <Ionicons name="person" size={14} color="#fff" />
          </View>
        </View>
      </View>
      {/* Bottom border with gradient mask */}
      <LinearGradient
        colors={["transparent", "rgba(255,68,68,0.1)", "transparent"]}
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
    backgroundColor: THEME.accent,
    justifyContent: "center",
    alignItems: "center",
    shadowColor: THEME.accent,
    shadowOffset: { width: 0, height: 0 },
    shadowOpacity: 0.5,
    shadowRadius: 8,
    elevation: 6,
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
