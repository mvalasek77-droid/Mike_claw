import React, { useState } from "react";
import {
  View,
  Text,
  Modal,
  Pressable,
  TextInput,
  TouchableOpacity,
  ScrollView,
  StyleSheet,
  KeyboardAvoidingView,
  Platform,
} from "react-native";
import { Ionicons } from "@expo/vector-icons";
import * as Haptics from "expo-haptics";
import { useApp } from "../lib/AppContext";
import { THEME } from "../lib/data";
import { PLAYLIST_NAME_MAX } from "../lib/storage";

interface SaveToPlaylistSheetProps {
  visible: boolean;
  videoId: string;
  onClose: () => void;
}

/**
 * The Save picker. "Saved" is the built-in quick list every video can go in;
 * anything below it is a playlist the person made themselves.
 */
export default function SaveToPlaylistSheet({
  visible,
  videoId,
  onClose,
}: SaveToPlaylistSheetProps) {
  const {
    playlists,
    isSaved,
    toggleSaved,
    createPlaylist,
    togglePlaylistVideo,
  } = useApp();

  const [creating, setCreating] = useState(false);
  const [name, setName] = useState("");
  const [error, setError] = useState<string | null>(null);

  const saved = isSaved(videoId);

  function reset() {
    setCreating(false);
    setName("");
    setError(null);
  }

  function close() {
    reset();
    onClose();
  }

  async function handleCreate() {
    const trimmed = name.trim();
    if (!trimmed) return;
    const created = await createPlaylist(trimmed);
    if (!created) {
      setError("You already have a playlist with that name.");
      return;
    }
    await togglePlaylistVideo(created.id, videoId);
    reset();
  }

  return (
    <Modal
      visible={visible}
      transparent
      animationType="slide"
      onRequestClose={close}
    >
      <Pressable
        style={styles.backdrop}
        onPress={close}
        accessibilityLabel="Close"
      />
      <KeyboardAvoidingView
        behavior={Platform.OS === "ios" ? "padding" : undefined}
        style={styles.sheetWrap}
      >
        <View style={styles.sheet}>
          <View style={styles.grabber} />
          <View style={styles.headerRow}>
            <Text style={styles.title} accessibilityRole="header">
              Save to…
            </Text>
            <TouchableOpacity
              onPress={close}
              hitSlop={{ top: 10, bottom: 10, left: 10, right: 10 }}
              accessibilityRole="button"
              accessibilityLabel="Close"
            >
              <Ionicons name="close" size={22} color={THEME.textSecondary} />
            </TouchableOpacity>
          </View>

          <ScrollView
            style={styles.list}
            keyboardShouldPersistTaps="handled"
            showsVerticalScrollIndicator={false}
          >
            <TouchableOpacity
              style={styles.row}
              onPress={() => toggleSaved(videoId)}
              accessibilityRole="checkbox"
              accessibilityState={{ checked: saved }}
              accessibilityLabel="Saved"
            >
              <Ionicons
                name={saved ? "checkbox" : "square-outline"}
                size={22}
                color={saved ? THEME.accent : THEME.textSecondary}
              />
              <View style={{ flex: 1 }}>
                <Text style={styles.rowLabel}>Saved</Text>
                <Text style={styles.rowMeta}>Your quick list</Text>
              </View>
            </TouchableOpacity>

            {playlists.map((p) => {
              const inList = p.videoIds.includes(videoId);
              return (
                <TouchableOpacity
                  key={p.id}
                  style={styles.row}
                  onPress={() => togglePlaylistVideo(p.id, videoId)}
                  accessibilityRole="checkbox"
                  accessibilityState={{ checked: inList }}
                  accessibilityLabel={p.name}
                >
                  <Ionicons
                    name={inList ? "checkbox" : "square-outline"}
                    size={22}
                    color={inList ? THEME.accent : THEME.textSecondary}
                  />
                  <View style={{ flex: 1 }}>
                    <Text style={styles.rowLabel} numberOfLines={1}>
                      {p.name}
                    </Text>
                    <Text style={styles.rowMeta}>
                      {p.videoIds.length}{" "}
                      {p.videoIds.length === 1 ? "video" : "videos"}
                    </Text>
                  </View>
                </TouchableOpacity>
              );
            })}
          </ScrollView>

          {creating ? (
            <View style={styles.createBox}>
              <TextInput
                style={styles.input}
                placeholder="Playlist name"
                placeholderTextColor={THEME.textSecondary}
                value={name}
                onChangeText={(t) => {
                  setName(t);
                  setError(null);
                }}
                maxLength={PLAYLIST_NAME_MAX}
                autoFocus
                returnKeyType="done"
                onSubmitEditing={handleCreate}
                accessibilityLabel="New playlist name"
              />
              {error && <Text style={styles.error}>{error}</Text>}
              <View style={styles.createActions}>
                <TouchableOpacity
                  onPress={reset}
                  accessibilityRole="button"
                  accessibilityLabel="Cancel new playlist"
                >
                  <Text style={styles.cancel}>Cancel</Text>
                </TouchableOpacity>
                <TouchableOpacity
                  onPress={handleCreate}
                  disabled={!name.trim()}
                  accessibilityRole="button"
                  accessibilityLabel="Create playlist"
                >
                  <Text style={[styles.create, !name.trim() && { opacity: 0.4 }]}>
                    Create
                  </Text>
                </TouchableOpacity>
              </View>
            </View>
          ) : (
            <TouchableOpacity
              style={styles.newBtn}
              onPress={() => {
                Haptics.selectionAsync();
                setCreating(true);
              }}
              accessibilityRole="button"
              accessibilityLabel="New playlist"
            >
              <Ionicons name="add" size={20} color={THEME.accent} />
              <Text style={styles.newBtnText}>New playlist</Text>
            </TouchableOpacity>
          )}
        </View>
      </KeyboardAvoidingView>
    </Modal>
  );
}

const styles = StyleSheet.create({
  backdrop: { flex: 1, backgroundColor: "rgba(0,0,0,0.6)" },
  sheetWrap: { justifyContent: "flex-end" },
  sheet: {
    backgroundColor: THEME.bgSecondary,
    borderTopLeftRadius: 18,
    borderTopRightRadius: 18,
    paddingBottom: 34,
    borderTopWidth: 1,
    borderColor: THEME.border,
    maxHeight: "78%",
  },
  grabber: {
    width: 36,
    height: 4,
    borderRadius: 2,
    backgroundColor: THEME.bgHover,
    alignSelf: "center",
    marginTop: 8,
    marginBottom: 6,
  },
  headerRow: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
    paddingHorizontal: 18,
    paddingVertical: 10,
  },
  title: { color: THEME.textPrimary, fontSize: 18, fontWeight: "700" },
  list: { paddingHorizontal: 6 },
  row: {
    flexDirection: "row",
    alignItems: "center",
    gap: 14,
    paddingVertical: 13,
    paddingHorizontal: 12,
  },
  rowLabel: { color: THEME.textPrimary, fontSize: 15, fontWeight: "500" },
  rowMeta: { color: THEME.textSecondary, fontSize: 12, marginTop: 2 },
  newBtn: {
    flexDirection: "row",
    alignItems: "center",
    gap: 8,
    paddingHorizontal: 18,
    paddingTop: 14,
    marginTop: 6,
    borderTopWidth: 1,
    borderTopColor: THEME.border,
  },
  newBtnText: { color: THEME.accent, fontSize: 15, fontWeight: "600" },
  createBox: {
    paddingHorizontal: 18,
    paddingTop: 14,
    marginTop: 6,
    borderTopWidth: 1,
    borderTopColor: THEME.border,
    gap: 10,
  },
  input: {
    backgroundColor: THEME.bgTertiary,
    borderWidth: 1,
    borderColor: THEME.border,
    borderRadius: 10,
    paddingHorizontal: 12,
    paddingVertical: 10,
    color: THEME.textPrimary,
    fontSize: 15,
  },
  error: { color: THEME.accent, fontSize: 13 },
  createActions: {
    flexDirection: "row",
    justifyContent: "flex-end",
    gap: 20,
  },
  cancel: { color: THEME.textSecondary, fontSize: 15, fontWeight: "600" },
  create: { color: THEME.accent, fontSize: 15, fontWeight: "700" },
});
