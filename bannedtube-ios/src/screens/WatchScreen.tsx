import React, { useState, useEffect } from "react";
import {
  View,
  Text,
  ScrollView,
  TextInput,
  TouchableOpacity,
  StyleSheet,
} from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { LinearGradient } from "expo-linear-gradient";
import { Ionicons } from "@expo/vector-icons";
import * as Haptics from "expo-haptics";
import Avatar from "../components/Avatar";
import VideoCard from "../components/VideoCard";
import { useApp } from "../lib/AppContext";
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
  const [liked, setLiked] = useState(false);

  function handleLike() {
    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
    setLiked(!liked);
  }

  return (
    <View style={styles.commentRow} accessibilityRole="text">
      <Avatar color={comment.avatarColor} initial={comment.initial} size={32} />
      <View style={styles.commentContent}>
        <View style={styles.commentHeader}>
          <Text style={styles.commentAuthor}>{comment.author}</Text>
          <Text style={styles.commentTime}>{comment.timeAgo}</Text>
        </View>
        <Text style={styles.commentText}>{comment.text}</Text>
        <View style={styles.commentActions}>
          <TouchableOpacity
            style={styles.commentAction}
            onPress={handleLike}
            accessibilityRole="button"
            accessibilityLabel={`Like comment, ${comment.likes} likes`}
          >
            <Ionicons
              name={liked ? "thumbs-up" : "thumbs-up-outline"}
              size={14}
              color={liked ? THEME.accent : THEME.textSecondary}
            />
            <Text
              style={[
                styles.commentActionText,
                liked && { color: THEME.accent },
              ]}
            >
              {(liked ? comment.likes + 1 : comment.likes).toLocaleString()}
            </Text>
          </TouchableOpacity>
          {comment.replies && comment.replies.length > 0 && (
            <TouchableOpacity
              onPress={() => {
                Haptics.selectionAsync();
                setShowReplies(!showReplies);
              }}
              style={styles.commentAction}
              accessibilityRole="button"
              accessibilityLabel={`${showReplies ? "Hide" : "Show"} ${comment.replies.length} replies`}
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
  const {
    isLiked, isDisliked, toggleLike, toggleDislike,
    isSubscribed, toggleSubscription,
    isSaved, toggleSaved,
    addWatchHistory, addComment, getVideoComments,
  } = useApp();

  const [playing, setPlaying] = useState(false);
  const [commentText, setCommentText] = useState("");
  const liked = isLiked(video.id);
  const disliked = isDisliked(video.id);
  const subscribed = isSubscribed(video.channel.id);
  const saved = isSaved(video.id);
  const relatedVideos = videos.filter((v) => v.id !== video.id).slice(0, 6);
  const builtInComments = getComments();
  const userComments = getVideoComments(video.id);
  const allComments = [...userComments, ...builtInComments];

  useEffect(() => {
    addWatchHistory(video.id, 0);
  }, [video.id]);

  async function handleLike() {
    await toggleLike(video.id);
  }

  async function handleDislike() {
    await toggleDislike(video.id);
  }

  async function handleSubscribe() {
    await toggleSubscription(video.channel.id);
  }

  async function handleSave() {
    await toggleSaved(video.id);
  }

  async function handleSubmitComment() {
    const trimmed = commentText.trim();
    if (!trimmed) return;
    await addComment(video.id, trimmed);
    setCommentText("");
  }

  return (
    <SafeAreaView style={styles.container} edges={["top"]}>
      <TouchableOpacity
        style={styles.backBtn}
        onPress={onBack}
        activeOpacity={0.6}
        accessibilityRole="button"
        accessibilityLabel="Go back"
      >
        <Ionicons name="chevron-back" size={24} color={THEME.textPrimary} />
      </TouchableOpacity>

      <ScrollView showsVerticalScrollIndicator={false}>
        <TouchableOpacity
          style={styles.player}
          onPress={() => {
            Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
            setPlaying(!playing);
          }}
          activeOpacity={0.9}
          accessibilityRole="button"
          accessibilityLabel={playing ? "Pause video" : "Play video"}
        >
          <LinearGradient
            colors={[video.thumbnailColors[0], video.thumbnailColors[1]]}
            start={{ x: 0, y: 0 }}
            end={{ x: 1, y: 1 }}
            style={StyleSheet.absoluteFill}
          />
          <LinearGradient
            colors={["rgba(0,0,0,0.4)", "transparent", "rgba(0,0,0,0.5)"]}
            locations={[0, 0.4, 1]}
            style={StyleSheet.absoluteFill}
          />

          {!playing && (
            <View style={styles.playOverlay}>
              <View style={styles.playGlow} />
              <View style={styles.playCircle}>
                <Ionicons
                  name="play"
                  size={32}
                  color="#fff"
                  style={{ marginLeft: 4 }}
                />
              </View>
            </View>
          )}

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
          <Text style={styles.title} accessibilityRole="header">
            {video.title}
          </Text>

          <View style={styles.channelRow}>
            <TouchableOpacity
              style={styles.channelInfo}
              onPress={() => onChannelPress(video.channel.id)}
              activeOpacity={0.7}
              accessibilityRole="button"
              accessibilityLabel={`View ${video.channel.name} channel`}
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
            <TouchableOpacity
              style={[
                styles.subscribeBtn,
                subscribed && styles.subscribedBtn,
              ]}
              onPress={handleSubscribe}
              activeOpacity={0.7}
              accessibilityRole="button"
              accessibilityLabel={subscribed ? "Unsubscribe" : "Subscribe"}
            >
              <Text
                style={[
                  styles.subscribeBtnText,
                  subscribed && styles.subscribedBtnText,
                ]}
              >
                {subscribed ? "Subscribed" : "Subscribe"}
              </Text>
            </TouchableOpacity>
          </View>

          <ScrollView
            horizontal
            showsHorizontalScrollIndicator={false}
            contentContainerStyle={styles.actionsRow}
          >
            <TouchableOpacity
              style={[styles.actionPill, liked && styles.actionPillActive]}
              onPress={handleLike}
              accessibilityRole="button"
              accessibilityLabel={`Like, ${video.likes} likes`}
            >
              <Ionicons
                name={liked ? "thumbs-up" : "thumbs-up-outline"}
                size={18}
                color={liked ? THEME.accent : THEME.textPrimary}
              />
              <Text
                style={[
                  styles.actionPillText,
                  liked && { color: THEME.accent },
                ]}
              >
                {((liked ? video.likes + 1 : video.likes) / 1000).toFixed(0)}K
              </Text>
            </TouchableOpacity>
            <TouchableOpacity
              style={[styles.actionPill, disliked && styles.actionPillActive]}
              onPress={handleDislike}
              accessibilityRole="button"
              accessibilityLabel={disliked ? "Remove dislike" : "Dislike"}
            >
              <Ionicons
                name={disliked ? "thumbs-down" : "thumbs-down-outline"}
                size={18}
                color={disliked ? THEME.accent : THEME.textPrimary}
              />
            </TouchableOpacity>
            <TouchableOpacity
              style={styles.actionPill}
              accessibilityRole="button"
              accessibilityLabel="Share"
            >
              <Ionicons
                name="share-outline"
                size={18}
                color={THEME.textPrimary}
              />
              <Text style={styles.actionPillText}>Share</Text>
            </TouchableOpacity>
            <TouchableOpacity
              style={[styles.actionPill, saved && styles.actionPillActive]}
              onPress={handleSave}
              accessibilityRole="button"
              accessibilityLabel={saved ? "Unsave" : "Save"}
            >
              <Ionicons
                name={saved ? "bookmark" : "bookmark-outline"}
                size={18}
                color={saved ? THEME.accent : THEME.textPrimary}
              />
              <Text
                style={[
                  styles.actionPillText,
                  saved && { color: THEME.accent },
                ]}
              >
                {saved ? "Saved" : "Save"}
              </Text>
            </TouchableOpacity>
            <TouchableOpacity
              style={styles.actionPill}
              accessibilityRole="button"
              accessibilityLabel="Report"
            >
              <Ionicons
                name="flag-outline"
                size={18}
                color={THEME.textPrimary}
              />
            </TouchableOpacity>
          </ScrollView>

          <View style={styles.descriptionCard}>
            <LinearGradient
              colors={["rgba(255,68,68,0.04)", "transparent"]}
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

          <Text style={styles.commentsHeader}>
            {allComments.length} Comments
          </Text>

          <View style={styles.commentInputRow}>
            <TextInput
              style={styles.commentInput}
              placeholder="Add a comment..."
              placeholderTextColor={THEME.textSecondary}
              value={commentText}
              onChangeText={setCommentText}
              returnKeyType="send"
              onSubmitEditing={handleSubmitComment}
            />
            <TouchableOpacity
              onPress={handleSubmitComment}
              disabled={!commentText.trim()}
              style={[
                styles.commentSendBtn,
                !commentText.trim() && { opacity: 0.3 },
              ]}
              accessibilityRole="button"
              accessibilityLabel="Post comment"
            >
              <Ionicons name="send" size={18} color={THEME.accent} />
            </TouchableOpacity>
          </View>

          {allComments.map((comment) => (
            <CommentItem key={comment.id} comment={comment} />
          ))}

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
    shadowColor: THEME.accent,
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.4,
    shadowRadius: 12,
  },
  progressContainer: {
    position: "absolute",
    bottom: 0,
    left: 0,
    right: 0,
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
  subscribedBtn: {
    backgroundColor: THEME.bgTertiary,
    borderWidth: 1,
    borderColor: THEME.border,
  },
  subscribeBtnText: {
    color: "#fff",
    fontSize: 14,
    fontWeight: "600",
  },
  subscribedBtnText: {
    color: THEME.textSecondary,
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
  actionPillActive: {
    backgroundColor: "rgba(255,68,68,0.12)",
    borderWidth: 1,
    borderColor: "rgba(255,68,68,0.25)",
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
  commentInputRow: {
    flexDirection: "row",
    alignItems: "center",
    gap: 8,
    marginBottom: 16,
    backgroundColor: THEME.bgTertiary,
    borderRadius: 20,
    paddingHorizontal: 14,
    paddingVertical: 4,
  },
  commentInput: {
    flex: 1,
    color: THEME.textPrimary,
    fontSize: 14,
    paddingVertical: 8,
  },
  commentSendBtn: {
    padding: 4,
  },
  relatedHeader: {
    color: THEME.textPrimary,
    fontSize: 15,
    fontWeight: "600",
    marginTop: 10,
    marginBottom: 14,
  },
});
