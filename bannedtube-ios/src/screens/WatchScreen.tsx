import React, { useState } from "react";
import {
  View,
  Text,
  ScrollView,
  TouchableOpacity,
  StyleSheet,
} from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { LinearGradient } from "expo-linear-gradient";
import { Ionicons } from "@expo/vector-icons";
import Avatar from "../components/Avatar";
import VideoCard from "../components/VideoCard";
import {
  type Video,
  type Comment,
  videos,
  formatViews,
  formatSubscribers,
  getComments,
  THEME,
} from "../lib/data";

interface WatchScreenProps {
  video: Video;
  onBack: () => void;
  onVideoPress: (video: Video) => void;
  onChannelPress: (channelId: string) => void;
}

function CommentItem({ comment }: { comment: Comment }) {
  const [showReplies, setShowReplies] = useState(false);

  return (
    <View style={styles.commentRow}>
      <Avatar color={comment.avatarColor} initial={comment.initial} size={32} />
      <View style={styles.commentContent}>
        <View style={styles.commentHeader}>
          <Text style={styles.commentAuthor}>{comment.author}</Text>
          <Text style={styles.commentTime}>{comment.timeAgo}</Text>
        </View>
        <Text style={styles.commentText}>{comment.text}</Text>
        <View style={styles.commentActions}>
          <TouchableOpacity style={styles.commentAction}>
            <Ionicons name="thumbs-up-outline" size={14} color={THEME.textSecondary} />
            <Text style={styles.commentActionText}>
              {comment.likes.toLocaleString()}
            </Text>
          </TouchableOpacity>
          {comment.replies && comment.replies.length > 0 && (
            <TouchableOpacity
              onPress={() => setShowReplies(!showReplies)}
              style={styles.commentAction}
            >
              <Ionicons
                name={showReplies ? "chevron-up" : "chevron-down"}
                size={14}
                color="#60a5fa"
              />
              <Text style={[styles.commentActionText, { color: "#60a5fa" }]}>
                {comment.replies.length}{" "}
                {comment.replies.length === 1 ? "reply" : "replies"}
              </Text>
            </TouchableOpacity>
          )}
        </View>
        {showReplies &&
          comment.replies?.map((reply) => (
            <View key={reply.id} style={styles.replyRow}>
              <CommentItem comment={reply} />
            </View>
          ))}
      </View>
    </View>
  );
}

export default function WatchScreen({
  video,
  onBack,
  onVideoPress,
  onChannelPress,
}: WatchScreenProps) {
  const [playing, setPlaying] = useState(false);
  const relatedVideos = videos.filter((v) => v.id !== video.id).slice(0, 6);
  const comments = getComments();

  return (
    <SafeAreaView style={styles.container} edges={["top"]}>
      {/* Back button */}
      <TouchableOpacity style={styles.backBtn} onPress={onBack} activeOpacity={0.6}>
        <Ionicons name="chevron-back" size={24} color={THEME.textPrimary} />
      </TouchableOpacity>

      <ScrollView showsVerticalScrollIndicator={false}>
        {/* Video player */}
        <TouchableOpacity
          style={styles.player}
          onPress={() => setPlaying(!playing)}
          activeOpacity={0.9}
        >
          <LinearGradient
            colors={[video.thumbnailColors[0], video.thumbnailColors[1]]}
            start={{ x: 0, y: 0 }}
            end={{ x: 1, y: 1 }}
            style={StyleSheet.absoluteFill}
          />
          {/* Vignette masks */}
          <LinearGradient
            colors={["rgba(0,0,0,0.4)", "transparent", "rgba(0,0,0,0.5)"]}
            locations={[0, 0.4, 1]}
            style={StyleSheet.absoluteFill}
          />

          {!playing && (
            <View style={styles.playOverlay}>
              <View style={styles.playGlow} />
              <View style={styles.playCircle}>
                <Ionicons name="play" size={32} color="#fff" style={{ marginLeft: 4 }} />
              </View>
            </View>
          )}

          {/* Progress bar */}
          <View style={styles.progressContainer}>
            <View style={styles.progressTrack}>
              <View
                style={[
                  styles.progressFill,
                  { width: playing ? "35%" : "0%" },
                ]}
              />
            </View>
          </View>
        </TouchableOpacity>

        <View style={styles.content}>
          {/* Title */}
          <Text style={styles.title}>{video.title}</Text>

          {/* Channel row */}
          <View style={styles.channelRow}>
            <TouchableOpacity
              style={styles.channelInfo}
              onPress={() => onChannelPress(video.channel.id)}
              activeOpacity={0.7}
            >
              <Avatar
                color={video.channel.avatarColor}
                initial={video.channel.initial}
                size={40}
                borderColor="rgba(255,68,68,0.25)"
              />
              <View>
                <View style={styles.channelNameRow}>
                  <Text style={styles.channelName}>{video.channel.name}</Text>
                  {video.channel.verified && (
                    <Ionicons
                      name="checkmark-circle"
                      size={14}
                      color={THEME.textSecondary}
                    />
                  )}
                </View>
                <Text style={styles.channelSubs}>
                  {formatSubscribers(video.channel.subscribers)}
                </Text>
              </View>
            </TouchableOpacity>
            <TouchableOpacity style={styles.subscribeBtn} activeOpacity={0.7}>
              <Text style={styles.subscribeBtnText}>Subscribe</Text>
            </TouchableOpacity>
          </View>

          {/* Action buttons */}
          <ScrollView
            horizontal
            showsHorizontalScrollIndicator={false}
            contentContainerStyle={styles.actionsRow}
          >
            <TouchableOpacity style={styles.actionPill}>
              <Ionicons name="thumbs-up-outline" size={18} color={THEME.textPrimary} />
              <Text style={styles.actionPillText}>
                {(video.likes / 1000).toFixed(0)}K
              </Text>
            </TouchableOpacity>
            <TouchableOpacity style={styles.actionPill}>
              <Ionicons name="thumbs-down-outline" size={18} color={THEME.textPrimary} />
            </TouchableOpacity>
            <TouchableOpacity style={styles.actionPill}>
              <Ionicons name="share-outline" size={18} color={THEME.textPrimary} />
              <Text style={styles.actionPillText}>Share</Text>
            </TouchableOpacity>
            <TouchableOpacity style={styles.actionPill}>
              <Ionicons name="download-outline" size={18} color={THEME.textPrimary} />
              <Text style={styles.actionPillText}>Save</Text>
            </TouchableOpacity>
            <TouchableOpacity style={styles.actionPill}>
              <Ionicons name="flag-outline" size={18} color={THEME.textPrimary} />
            </TouchableOpacity>
          </ScrollView>

          {/* Description card with masked edges */}
          <View style={styles.descriptionCard}>
            <LinearGradient
              colors={["rgba(255,68,68,0.05)", "transparent"]}
              start={{ x: 0, y: 0 }}
              end={{ x: 1, y: 1 }}
              style={StyleSheet.absoluteFill}
            />
            <Text style={styles.descMeta}>
              {formatViews(video.views)} · {video.uploadedAt}
            </Text>
            <Text style={styles.descText}>{video.description}</Text>
            <View style={styles.tagsRow}>
              {video.tags.map((tag) => (
                <Text key={tag} style={styles.tag}>
                  #{tag}
                </Text>
              ))}
            </View>
          </View>

          {/* Comments */}
          <Text style={styles.commentsHeader}>
            {comments.length} Comments
          </Text>
          {comments.map((comment) => (
            <CommentItem key={comment.id} comment={comment} />
          ))}

          {/* Related videos */}
          <Text style={styles.relatedHeader}>Up next</Text>
          {relatedVideos.map((v) => (
            <VideoCard
              key={v.id}
              video={v}
              onPress={onVideoPress}
              layout="list"
            />
          ))}

          <View style={{ height: 40 }} />
        </View>
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: THEME.bgPrimary,
  },
  backBtn: {
    position: "absolute",
    top: 54,
    left: 12,
    zIndex: 10,
    width: 36,
    height: 36,
    borderRadius: 18,
    backgroundColor: "rgba(0,0,0,0.5)",
    justifyContent: "center",
    alignItems: "center",
  },
  player: {
    width: "100%",
    aspectRatio: 16 / 9,
    justifyContent: "center",
    alignItems: "center",
  },
  playOverlay: {
    justifyContent: "center",
    alignItems: "center",
  },
  playGlow: {
    position: "absolute",
    width: 80,
    height: 80,
    borderRadius: 40,
    backgroundColor: "rgba(255,68,68,0.2)",
  },
  playCircle: {
    width: 64,
    height: 64,
    borderRadius: 32,
    backgroundColor: "rgba(255,68,68,0.85)",
    justifyContent: "center",
    alignItems: "center",
  },
  progressContainer: {
    position: "absolute",
    bottom: 0,
    left: 0,
    right: 0,
    paddingHorizontal: 0,
  },
  progressTrack: {
    height: 3,
    backgroundColor: "rgba(255,255,255,0.2)",
  },
  progressFill: {
    height: 3,
    backgroundColor: THEME.accent,
  },
  content: {
    paddingHorizontal: 14,
    paddingTop: 14,
  },
  title: {
    color: THEME.textPrimary,
    fontSize: 18,
    fontWeight: "600",
    lineHeight: 24,
    marginBottom: 12,
  },
  channelRow: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
    marginBottom: 14,
  },
  channelInfo: {
    flexDirection: "row",
    alignItems: "center",
    gap: 10,
    flex: 1,
  },
  channelNameRow: {
    flexDirection: "row",
    alignItems: "center",
    gap: 4,
  },
  channelName: {
    color: THEME.textPrimary,
    fontSize: 14,
    fontWeight: "500",
  },
  channelSubs: {
    color: THEME.textSecondary,
    fontSize: 12,
    marginTop: 1,
  },
  subscribeBtn: {
    backgroundColor: THEME.accent,
    paddingHorizontal: 16,
    paddingVertical: 8,
    borderRadius: 20,
  },
  subscribeBtnText: {
    color: "#fff",
    fontSize: 14,
    fontWeight: "600",
  },
  actionsRow: {
    gap: 8,
    paddingBottom: 14,
  },
  actionPill: {
    flexDirection: "row",
    alignItems: "center",
    gap: 6,
    backgroundColor: THEME.bgTertiary,
    paddingHorizontal: 14,
    paddingVertical: 8,
    borderRadius: 20,
  },
  actionPillText: {
    color: THEME.textPrimary,
    fontSize: 13,
    fontWeight: "500",
  },
  descriptionCard: {
    backgroundColor: THEME.bgTertiary,
    borderRadius: 12,
    padding: 14,
    marginBottom: 18,
    overflow: "hidden",
  },
  descMeta: {
    color: THEME.textPrimary,
    fontSize: 13,
    fontWeight: "600",
    marginBottom: 6,
  },
  descText: {
    color: THEME.textPrimary,
    fontSize: 14,
    lineHeight: 20,
  },
  tagsRow: {
    flexDirection: "row",
    flexWrap: "wrap",
    gap: 8,
    marginTop: 8,
  },
  tag: {
    color: "#60a5fa",
    fontSize: 12,
  },
  commentsHeader: {
    color: THEME.textPrimary,
    fontSize: 15,
    fontWeight: "600",
    marginBottom: 14,
  },
  commentRow: {
    flexDirection: "row",
    gap: 10,
    marginBottom: 16,
  },
  commentContent: {
    flex: 1,
  },
  commentHeader: {
    flexDirection: "row",
    alignItems: "center",
    gap: 8,
    marginBottom: 4,
  },
  commentAuthor: {
    color: THEME.textPrimary,
    fontSize: 13,
    fontWeight: "500",
  },
  commentTime: {
    color: THEME.textSecondary,
    fontSize: 11,
  },
  commentText: {
    color: THEME.textPrimary,
    fontSize: 13,
    lineHeight: 18,
    marginBottom: 6,
  },
  commentActions: {
    flexDirection: "row",
    gap: 16,
  },
  commentAction: {
    flexDirection: "row",
    alignItems: "center",
    gap: 4,
  },
  commentActionText: {
    color: THEME.textSecondary,
    fontSize: 12,
  },
  replyRow: {
    marginTop: 10,
    marginLeft: 4,
    borderLeftWidth: 2,
    borderLeftColor: THEME.border,
    paddingLeft: 12,
  },
  relatedHeader: {
    color: THEME.textPrimary,
    fontSize: 15,
    fontWeight: "600",
    marginTop: 10,
    marginBottom: 14,
  },
});
