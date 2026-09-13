import React, { useEffect, useState, useCallback } from "react";
import {
  View,
  Text,
  TextInput,
  TouchableOpacity,
  StyleSheet,
  ScrollView,
  Switch,
  Alert,
  Share,
  Linking,
  KeyboardAvoidingView,
  Platform,
} from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { Ionicons } from "@expo/vector-icons";
import * as Haptics from "expo-haptics";
import * as Clipboard from "expo-clipboard";
import GlassCard from "../components/GlassCard";
import { THEME } from "../lib/data";
import {
  BugReports,
  BUG_CATEGORIES,
  SUPPORT_EMAIL,
  formatReport,
  type BugCategory,
  type BugReport,
} from "../lib/bugReports";

interface BugReportScreenProps {
  onBack: () => void;
  /** Pre-fills the report when opened from a specific video. */
  videoId?: string;
  videoTitle?: string;
}

export default function BugReportScreen({
  onBack,
  videoId,
  videoTitle,
}: BugReportScreenProps) {
  const [category, setCategory] = useState<BugCategory>(
    videoId ? "Playback" : "Something else"
  );
  const [summary, setSummary] = useState("");
  const [details, setDetails] = useState("");
  const [steps, setSteps] = useState("");
  const [includeDiagnostics, setIncludeDiagnostics] = useState(true);
  const [submitting, setSubmitting] = useState(false);
  const [past, setPast] = useState<BugReport[]>([]);

  const refresh = useCallback(async () => {
    setPast(await BugReports.list());
  }, []);

  useEffect(() => {
    refresh();
  }, [refresh]);

  const canSubmit = summary.trim().length > 0 && details.trim().length > 0;

  async function sendReport(report: BugReport) {
    const body = formatReport(report);
    try {
      if (SUPPORT_EMAIL) {
        const url = `mailto:${SUPPORT_EMAIL}?subject=${encodeURIComponent(
          `BannedTube bug: ${report.summary}`
        )}&body=${encodeURIComponent(body)}`;
        if (await Linking.canOpenURL(url)) {
          await Linking.openURL(url);
          return;
        }
      }
      await Share.share({
        message: body,
        title: `BannedTube bug: ${report.summary}`,
      });
    } catch {
      await Clipboard.setStringAsync(body);
      Alert.alert(
        "Copied instead",
        "The share sheet was unavailable, so the report was copied to your clipboard."
      );
    }
  }

  async function handleSubmit() {
    if (!canSubmit || submitting) return;
    setSubmitting(true);
    try {
      const report = await BugReports.create({
        category,
        summary,
        details,
        steps,
        videoId,
        includeDiagnostics,
      });
      Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
      setSummary("");
      setDetails("");
      setSteps("");
      await refresh();

      Alert.alert(
        "Report saved",
        "It is stored on this device. Send it now so it reaches someone who can fix it?",
        [
          { text: "Not now", style: "cancel" },
          { text: "Send", onPress: () => sendReport(report) },
        ]
      );
    } catch {
      Alert.alert("Could not save", "Something went wrong saving the report.");
    } finally {
      setSubmitting(false);
    }
  }

  function handleDelete(report: BugReport) {
    Alert.alert("Delete report?", report.summary, [
      { text: "Cancel", style: "cancel" },
      {
        text: "Delete",
        style: "destructive",
        onPress: async () => {
          await BugReports.remove(report.id);
          Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
          await refresh();
        },
      },
    ]);
  }

  return (
    <SafeAreaView style={styles.container} edges={["top"]}>
      <View style={styles.header}>
        <TouchableOpacity
          onPress={onBack}
          style={styles.backBtn}
          accessibilityRole="button"
          accessibilityLabel="Go back"
        >
          <Ionicons name="chevron-back" size={24} color={THEME.textPrimary} />
        </TouchableOpacity>
        <Text style={styles.headerTitle} accessibilityRole="header">
          Report a bug
        </Text>
      </View>

      <KeyboardAvoidingView
        style={{ flex: 1 }}
        behavior={Platform.OS === "ios" ? "padding" : undefined}
      >
        <ScrollView
          contentContainerStyle={styles.scroll}
          showsVerticalScrollIndicator={false}
          keyboardDismissMode="interactive"
        >
          {videoTitle && (
            <GlassCard style={styles.contextCard}>
              <Ionicons name="videocam-outline" size={16} color={THEME.accent} />
              <Text style={styles.contextText} numberOfLines={2}>
                Reporting a problem with “{videoTitle}”
              </Text>
            </GlassCard>
          )}

          <Text style={styles.label}>What kind of problem is it?</Text>
          <View style={styles.chipRow}>
            {BUG_CATEGORIES.map((c) => {
              const active = c === category;
              return (
                <TouchableOpacity
                  key={c}
                  style={[styles.chip, active && styles.chipActive]}
                  onPress={() => {
                    Haptics.selectionAsync();
                    setCategory(c);
                  }}
                  accessibilityRole="button"
                  accessibilityState={{ selected: active }}
                  accessibilityLabel={c}
                >
                  <Text
                    style={[styles.chipText, active && styles.chipTextActive]}
                  >
                    {c}
                  </Text>
                </TouchableOpacity>
              );
            })}
          </View>

          <Text style={styles.label}>Summary</Text>
          <TextInput
            style={styles.input}
            placeholder="One line describing the problem"
            placeholderTextColor={THEME.textSecondary}
            value={summary}
            onChangeText={setSummary}
            maxLength={120}
            accessibilityLabel="Bug summary"
          />

          <Text style={styles.label}>What happened?</Text>
          <TextInput
            style={[styles.input, styles.multiline]}
            placeholder="What did you expect, and what happened instead?"
            placeholderTextColor={THEME.textSecondary}
            value={details}
            onChangeText={setDetails}
            multiline
            textAlignVertical="top"
            accessibilityLabel="Bug details"
          />

          <Text style={styles.label}>Steps to reproduce (optional)</Text>
          <TextInput
            style={[styles.input, styles.multiline]}
            placeholder={"1. Open …\n2. Tap …\n3. See …"}
            placeholderTextColor={THEME.textSecondary}
            value={steps}
            onChangeText={setSteps}
            multiline
            textAlignVertical="top"
            accessibilityLabel="Steps to reproduce"
          />

          <View style={styles.diagnosticsRow}>
            <View style={{ flex: 1 }}>
              <Text style={styles.diagnosticsTitle}>Attach diagnostics</Text>
              <Text style={styles.diagnosticsBody}>
                Adds your app version, device platform and OS version, plus the
                last few recorded errors. No personal details, watch history or
                comments are included.
              </Text>
            </View>
            <Switch
              value={includeDiagnostics}
              onValueChange={(v) => {
                Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
                setIncludeDiagnostics(v);
              }}
              trackColor={{ false: THEME.bgTertiary, true: THEME.accent }}
              thumbColor="#fff"
              accessibilityLabel="Attach diagnostics"
            />
          </View>

          <TouchableOpacity
            style={[styles.submitBtn, !canSubmit && styles.submitBtnDisabled]}
            onPress={handleSubmit}
            disabled={!canSubmit || submitting}
            accessibilityRole="button"
            accessibilityLabel="Submit bug report"
            accessibilityState={{ disabled: !canSubmit || submitting }}
          >
            <Text style={styles.submitBtnText}>
              {submitting ? "Saving…" : "Submit report"}
            </Text>
          </TouchableOpacity>

          <Text style={styles.disclaimer}>
            Reports are kept on this device. Sending one opens your share sheet
            so you choose where it goes — nothing is uploaded automatically.
          </Text>

          {past.length > 0 && (
            <View style={styles.pastSection}>
              <Text style={styles.pastHeader}>
                Your reports ({past.length})
              </Text>
              {past.map((r) => (
                <GlassCard key={r.id} style={styles.pastCard}>
                  <View style={styles.pastTop}>
                    <View style={{ flex: 1 }}>
                      <Text style={styles.pastSummary} numberOfLines={2}>
                        {r.summary}
                      </Text>
                      <Text style={styles.pastMeta}>
                        {r.category} ·{" "}
                        {new Date(r.createdAt).toLocaleDateString()}
                        {r.diagnostics ? " · diagnostics attached" : ""}
                      </Text>
                    </View>
                  </View>
                  <View style={styles.pastActions}>
                    <TouchableOpacity
                      style={styles.pastAction}
                      onPress={() => sendReport(r)}
                      accessibilityRole="button"
                      accessibilityLabel={`Send report: ${r.summary}`}
                    >
                      <Ionicons
                        name="share-outline"
                        size={16}
                        color={THEME.textPrimary}
                      />
                      <Text style={styles.pastActionText}>Send</Text>
                    </TouchableOpacity>
                    <TouchableOpacity
                      style={styles.pastAction}
                      onPress={async () => {
                        await Clipboard.setStringAsync(formatReport(r));
                        Haptics.notificationAsync(
                          Haptics.NotificationFeedbackType.Success
                        );
                        Alert.alert("Copied", "Report copied to clipboard.");
                      }}
                      accessibilityRole="button"
                      accessibilityLabel={`Copy report: ${r.summary}`}
                    >
                      <Ionicons
                        name="copy-outline"
                        size={16}
                        color={THEME.textPrimary}
                      />
                      <Text style={styles.pastActionText}>Copy</Text>
                    </TouchableOpacity>
                    <TouchableOpacity
                      style={styles.pastAction}
                      onPress={() => handleDelete(r)}
                      accessibilityRole="button"
                      accessibilityLabel={`Delete report: ${r.summary}`}
                    >
                      <Ionicons
                        name="trash-outline"
                        size={16}
                        color={THEME.accent}
                      />
                      <Text
                        style={[styles.pastActionText, { color: THEME.accent }]}
                      >
                        Delete
                      </Text>
                    </TouchableOpacity>
                  </View>
                </GlassCard>
              ))}
            </View>
          )}

          <View style={{ height: 60 }} />
        </ScrollView>
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: THEME.bgPrimary },
  header: {
    flexDirection: "row",
    alignItems: "center",
    paddingHorizontal: 8,
    paddingTop: 8,
    paddingBottom: 10,
    gap: 4,
  },
  backBtn: {
    width: 40,
    height: 40,
    justifyContent: "center",
    alignItems: "center",
  },
  headerTitle: {
    color: THEME.textPrimary,
    fontSize: 20,
    fontWeight: "700",
  },
  scroll: { paddingHorizontal: 16, paddingBottom: 40 },
  contextCard: {
    flexDirection: "row",
    alignItems: "center",
    gap: 8,
    marginBottom: 16,
  },
  contextText: { color: THEME.textSecondary, fontSize: 13, flex: 1 },
  label: {
    color: THEME.textSecondary,
    fontSize: 13,
    fontWeight: "600",
    textTransform: "uppercase",
    letterSpacing: 0.4,
    marginTop: 18,
    marginBottom: 8,
  },
  chipRow: { flexDirection: "row", flexWrap: "wrap", gap: 8 },
  chip: {
    paddingHorizontal: 14,
    paddingVertical: 8,
    borderRadius: 20,
    backgroundColor: THEME.bgSecondary,
    borderWidth: 1,
    borderColor: THEME.border,
  },
  chipActive: {
    backgroundColor: THEME.accentGlow,
    borderColor: THEME.accent,
  },
  chipText: { color: THEME.textSecondary, fontSize: 13, fontWeight: "500" },
  chipTextActive: { color: THEME.accent, fontWeight: "600" },
  input: {
    backgroundColor: THEME.bgSecondary,
    borderWidth: 1,
    borderColor: THEME.border,
    borderRadius: 12,
    paddingHorizontal: 14,
    paddingVertical: 12,
    color: THEME.textPrimary,
    fontSize: 15,
  },
  multiline: { minHeight: 110 },
  diagnosticsRow: {
    flexDirection: "row",
    alignItems: "center",
    gap: 14,
    marginTop: 22,
    backgroundColor: THEME.bgSecondary,
    borderWidth: 1,
    borderColor: THEME.border,
    borderRadius: 12,
    padding: 14,
  },
  diagnosticsTitle: {
    color: THEME.textPrimary,
    fontSize: 15,
    fontWeight: "600",
    marginBottom: 4,
  },
  diagnosticsBody: {
    color: THEME.textSecondary,
    fontSize: 12,
    lineHeight: 17,
  },
  submitBtn: {
    backgroundColor: THEME.accent,
    borderRadius: 14,
    paddingVertical: 15,
    alignItems: "center",
    marginTop: 22,
  },
  submitBtnDisabled: { opacity: 0.4 },
  submitBtnText: { color: "#fff", fontSize: 16, fontWeight: "700" },
  disclaimer: {
    color: THEME.textSecondary,
    fontSize: 12,
    lineHeight: 17,
    textAlign: "center",
    marginTop: 12,
  },
  pastSection: { marginTop: 32 },
  pastHeader: {
    color: THEME.textSecondary,
    fontSize: 13,
    fontWeight: "600",
    textTransform: "uppercase",
    letterSpacing: 0.4,
    marginBottom: 10,
  },
  pastCard: { marginBottom: 12 },
  pastTop: { flexDirection: "row", alignItems: "flex-start" },
  pastSummary: {
    color: THEME.textPrimary,
    fontSize: 15,
    fontWeight: "600",
  },
  pastMeta: { color: THEME.textSecondary, fontSize: 12, marginTop: 3 },
  pastActions: {
    flexDirection: "row",
    gap: 18,
    marginTop: 12,
    paddingTop: 10,
    borderTopWidth: 1,
    borderTopColor: THEME.border,
  },
  pastAction: { flexDirection: "row", alignItems: "center", gap: 5 },
  pastActionText: {
    color: THEME.textPrimary,
    fontSize: 13,
    fontWeight: "500",
  },
});
