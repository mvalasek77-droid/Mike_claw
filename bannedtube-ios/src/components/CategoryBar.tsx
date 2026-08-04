import React from "react";
import {
  ScrollView,
  TouchableOpacity,
  Text,
  StyleSheet,
} from "react-native";
import { THEME, categories } from "../lib/data";

interface CategoryBarProps {
  active: string;
  onChange: (category: string) => void;
}

export default function CategoryBar({ active, onChange }: CategoryBarProps) {
  return (
    <ScrollView
      horizontal
      showsHorizontalScrollIndicator={false}
      contentContainerStyle={styles.container}
    >
      {categories.map((cat) => (
        <TouchableOpacity
          key={cat}
          onPress={() => onChange(cat)}
          style={[styles.pill, active === cat && styles.pillActive]}
          activeOpacity={0.7}
        >
          <Text
            style={[styles.pillText, active === cat && styles.pillTextActive]}
          >
            {cat}
          </Text>
        </TouchableOpacity>
      ))}
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  container: {
    paddingHorizontal: 12,
    paddingVertical: 10,
    gap: 8,
  },
  pill: {
    paddingHorizontal: 14,
    paddingVertical: 7,
    borderRadius: 10,
    backgroundColor: THEME.bgTertiary,
  },
  pillActive: {
    backgroundColor: THEME.textPrimary,
  },
  pillText: {
    color: THEME.textPrimary,
    fontSize: 14,
    fontWeight: "500",
  },
  pillTextActive: {
    color: THEME.bgPrimary,
    fontWeight: "600",
  },
});
