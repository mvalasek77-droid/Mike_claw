import React, { useState, useRef, useEffect } from "react";
import {
  View,
  Text,
  TextInput,
  ScrollView,
  TouchableOpacity,
  StyleSheet,
  Animated,
  Dimensions,
  Platform,
} from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { LinearGradient } from "expo-linear-gradient";
import { Ionicons } from "@expo/vector-icons";
import * as Haptics from "expo-haptics";
import GlassCard from "../components/GlassCard";
import RoadmapScreen from "./RoadmapScreen";
import {
  THEME,
  getAITitleSuggestions,
  getAITrendingTopics,
  getCreatorInsights,
  formatCompact,
  type AIContentSuggestion,
  type AITrendingTopic,
  type CreatorInsight,
} from "../lib/data";

const { width: SCREEN_WIDTH } = Dimensions.get("window");

type StudioTab = "create" | "trends" | "insights" | "roadmap";

function ConfidenceBar({ value }: { value: number }) {
  const width = useRef(new Animated.Value(0)).current;

  useEffect(() => {
    Animated.timing(width, {
      toValue: value,
      duration: 800,
      useNativeDriver: false,
    }).start();
  }, [value]);

  const color =
    value >= 0.9 ? THEME.success : value >= 0.8 ? THEME.warning : THEME.info;

  return (
    <View style={confStyles.track}>
      <Animated.View
        style={[
          confStyles.fill,
          {
            backgroundColor: color,
            width: width.interpolate({
              inputRange: [0, 1],
              outputRange: ["0%", "100%"],
            }),
          },
        ]}
      />
    </View>
  );
}

const confStyles = StyleSheet.create({
  track: {
    height: 3,
    backgroundColor: "rgba(255,255,255,0.08)",
    borderRadius: 2,
    overflow: "hidden",
    marginTop: 8,
  },
  fill: {
    height: 3,
    borderRadius: 2,
  },
});

function TrendCard({ topic }: { topic: AITrendingTopic }) {
  const pulseAnim = useRef(new Animated.Value(1)).current;

  useEffect(() => {
    Animated.loop(
      Animated.sequence([
        Animated.timing(pulseAnim, {
          toValue: 1.05,
          duration: 2000,
          useNativeDriver: true,
        }),
        Animated.timing(pulseAnim, {
          toValue: 1,
          duration: 2000,
          useNativeDriver: true,
        }),
      ])
    ).start();
  }, []);

  return (
    <GlassCard style={styles.trendCard} accentGlow={topic.growth > 250}>
      <View style={styles.trendHeader}>
        <View style={styles.trendTitleRow}>
          <Animated.View style={{ transform: [{ scale: pulseAnim }] }}>
            <View style={styles.trendIcon}>
              <Ionicons name="trending-up" size={16} color={THEME.success} />
            </View>
          </Animated.View>
          <View style={{ flex: 1 }}>
            <Text style={styles.trendTitle}>{topic.topic}</Text>
            <Text style={styles.trendCategory}>{topic.category}</Text>
          </View>
          <View style={styles.growthBadge}>
            <Ionicons name="arrow-up" size={10} color={THEME.success} />
            <Text style={styles.growthText}>{topic.growth}%</Text>
          </View>
        </View>
      </View>
      <Text style={styles.trendAngle}>{topic.suggestedAngle}</Text>
      <View style={styles.keywordsRow}>
        {topic.relatedKeywords.slice(0, 3).map((kw) => (
          <View key={kw} style={styles.keywordChip}>
            <Text style={styles.keywordText}>#{kw.replace(/\s+/g, "")}</Text>
          </View>
        ))}
      </View>
    </GlassCard>
  );
}

function InsightCard({ insight }: { insight: CreatorInsight }) {
  const isPositive = insight.trend === "up";
  const isNegative = insight.trend === "down";
  const trendColor = isPositive
    ? THEME.success
    : isNegative
      ? THEME.accent
      : THEME.textSecondary;
  const trendIcon = isPositive
    ? "trending-up"
    : isNegative
      ? "trending-down"
      : "remove";

  return (
    <GlassCard style={styles.insightCard}>
      <View style={styles.insightHeader}>
        <Text style={styles.insightMetric}>{insight.metric}</Text>
        <View
          style={[styles.insightBadge, { backgroundColor: `${trendColor}20` }]}
        >
          <Ionicons name={trendIcon as any} size={12} color={trendColor} />
          <Text style={[styles.insightChange, { color: trendColor }]}>
            {insight.change > 0 ? "+" : ""}
            {insight.change}%
          </Text>
        </View>
      </View>
      <Text style={styles.insightValue}>{insight.value}</Text>
      <View style={styles.insightDivider} />
      <View style={styles.insightSuggestionRow}>
        <Ionicons name="bulb" size={14} color={THEME.warning} />
        <Text style={styles.insightSuggestion}>{insight.suggestion}</Text>
      </View>
    </GlassCard>
  );
}

export default function AIStudioScreen() {
  const [activeTab, setActiveTab] = useState<StudioTab>("create");
  const [topic, setTopic] = useState("");
  const [suggestions, setSuggestions] = useState<AIContentSuggestion[]>([]);
  const [isGenerating, setIsGenerating] = useState(false);
  const [copiedId, setCopiedId] = useState<string | null>(null);
  const [showRoadmap, setShowRoadmap] = useState(false);

  const fadeAnim = useRef(new Animated.Value(0)).current;
  const slideAnim = useRef(new Animated.Value(30)).current;

  const trendingTopics = getAITrendingTopics();
  const creatorInsights = getCreatorInsights();

  function handleGenerate() {
    if (!topic.trim()) return;
    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium);
    setIsGenerating(true);
    setSuggestions([]);
    fadeAnim.setValue(0);
    slideAnim.setValue(30);

    setTimeout(() => {
      const results = getAITitleSuggestions(topic);
      setSuggestions(results);
      setIsGenerating(false);
      Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
      Animated.parallel([
        Animated.timing(fadeAnim, {
          toValue: 1,
          duration: 500,
          useNativeDriver: true,
        }),
        Animated.timing(slideAnim, {
          toValue: 0,
          duration: 500,
          useNativeDriver: true,
        }),
      ]).start();
    }, 1500);
  }

  function handleCopy(id: string) {
    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
    setCopiedId(id);
    setTimeout(() => setCopiedId(null), 2000);
  }

  const tabs: { key: StudioTab; icon: string; label: string }[] = [
    { key: "create", icon: "sparkles", label: "Create" },
    { key: "trends", icon: "analytics", label: "Trends" },
    { key: "insights", icon: "bar-chart", label: "Insights" },
    { key: "roadmap", icon: "map", label: "Roadmap" },
  ] as const;

  return (
    <SafeAreaView style={styles.container} edges={["top"]}>
      <View style={styles.header}>
        <LinearGradient
          colors={["rgba(255,68,68,0.08)", "transparent"]}
          start={{ x: 0, y: 0 }}
          end={{ x: 1, y: 1 }}
          style={StyleSheet.absoluteFill}
        />
        <View style={styles.headerContent}>
          <View style={styles.headerTitleRow}>
            <View style={styles.aiIcon}>
              <Ionicons name="sparkles" size={18} color="#fff" />
            </View>
            <View>
              <Text style={styles.headerTitle}>AI Studio</Text>
              <Text style={styles.headerSubtitle}>
                Powered by BannedTube AI
              </Text>
            </View>
          </View>
        </View>

        <View style={styles.tabRow}>
          {tabs.map((tab) => (
            <TouchableOpacity
              key={tab.key}
              style={[
                styles.tabBtn,
                activeTab === tab.key && styles.tabBtnActive,
              ]}
              onPress={() => {
                Haptics.selectionAsync();
                setActiveTab(tab.key);
              }}
              activeOpacity={0.7}
              accessibilityRole="tab"
              accessibilityState={{ selected: activeTab === tab.key }}
              accessibilityLabel={`${tab.label} tab`}
            >
              <Ionicons
                name={tab.icon as any}
                size={16}
                color={
                  activeTab === tab.key ? THEME.accent : THEME.textSecondary
                }
              />
              <Text
                style={[
                  styles.tabText,
                  activeTab === tab.key && styles.tabTextActive,
                ]}
              >
                {tab.label}
              </Text>
            </TouchableOpacity>
          ))}
        </View>
      </View>

      {activeTab === "roadmap" ? (
        <View style={{ flex: 1 }}>
          <RoadmapScreen />
        </View>
      ) : (
      <ScrollView
        showsVerticalScrollIndicator={false}
        contentContainerStyle={styles.scrollContent}
        keyboardDismissMode="on-drag"
      >
        {activeTab === "create" && (
          <View>
            <GlassCard style={styles.inputCard} accentGlow>
              <Text style={styles.inputLabel}>
                What's your next video about?
              </Text>
              <View style={styles.inputRow}>
                <TextInput
                  style={styles.textInput}
                  placeholder="Enter a topic or idea..."
                  placeholderTextColor="#555"
                  value={topic}
                  onChangeText={setTopic}
                  returnKeyType="go"
                  onSubmitEditing={handleGenerate}
                  accessibilityLabel="Topic input"
                  accessibilityHint="Enter a topic to generate AI suggestions"
                />
                <TouchableOpacity
                  style={[
                    styles.generateBtn,
                    !topic.trim() && styles.generateBtnDisabled,
                  ]}
                  onPress={handleGenerate}
                  disabled={!topic.trim() || isGenerating}
                  activeOpacity={0.7}
                  accessibilityRole="button"
                  accessibilityLabel="Generate suggestions"
                >
                  {isGenerating ? (
                    <Animated.View
                      style={{
                        transform: [
                          {
                            rotate: fadeAnim.interpolate({
                              inputRange: [0, 1],
                              outputRange: ["0deg", "360deg"],
                            }),
                          },
                        ],
                      }}
                    >
                      <Ionicons name="sync" size={20} color="#fff" />
                    </Animated.View>
                  ) : (
                    <Ionicons name="sparkles" size={20} color="#fff" />
                  )}
                </TouchableOpacity>
              </View>
            </GlassCard>

            {isGenerating && (
              <View style={styles.loadingContainer}>
                <View style={styles.loadingDot} />
                <Text style={styles.loadingText}>
                  AI is analyzing trending patterns...
                </Text>
              </View>
            )}

            {suggestions.length > 0 && (
              <Animated.View
                style={{
                  opacity: fadeAnim,
                  transform: [{ translateY: slideAnim }],
                }}
              >
                <Text style={styles.sectionTitle}>
                  Title Suggestions
                </Text>
                {suggestions.map((s, i) => (
                  <GlassCard
                    key={s.id}
                    style={[styles.suggestionCard, { marginBottom: 12 }]}
                  >
                    <View style={styles.suggestionHeader}>
                      <View style={styles.suggestionRank}>
                        <Text style={styles.suggestionRankText}>
                          {i + 1}
                        </Text>
                      </View>
                      <View style={{ flex: 1 }}>
                        <Text style={styles.suggestionTitle}>
                          {s.content}
                        </Text>
                      </View>
                      <TouchableOpacity
                        onPress={() => handleCopy(s.id)}
                        style={styles.copyBtn}
                        accessibilityRole="button"
                        accessibilityLabel={`Copy suggestion ${i + 1}`}
                      >
                        <Ionicons
                          name={
                            copiedId === s.id
                              ? "checkmark"
                              : "copy-outline"
                          }
                          size={18}
                          color={
                            copiedId === s.id
                              ? THEME.success
                              : THEME.textSecondary
                          }
                        />
                      </TouchableOpacity>
                    </View>
                    <Text style={styles.suggestionReasoning}>
                      {s.reasoning}
                    </Text>
                    <View style={styles.confidenceRow}>
                      <Text style={styles.confidenceLabel}>
                        Confidence
                      </Text>
                      <Text style={styles.confidenceValue}>
                        {Math.round(s.confidence * 100)}%
                      </Text>
                    </View>
                    <ConfidenceBar value={s.confidence} />
                  </GlassCard>
                ))}

                <GlassCard style={styles.moreToolsCard}>
                  <Text style={styles.moreToolsTitle}>
                    More AI Tools Coming Soon
                  </Text>
                  <View style={styles.moreToolsGrid}>
                    {[
                      {
                        icon: "image",
                        label: "Thumbnail AI",
                        desc: "Generate concepts",
                      },
                      {
                        icon: "document-text",
                        label: "Script Writer",
                        desc: "Draft outlines",
                      },
                      {
                        icon: "calendar",
                        label: "Smart Schedule",
                        desc: "Optimal upload times",
                      },
                      {
                        icon: "pricetag",
                        label: "Tag Generator",
                        desc: "SEO-optimized tags",
                      },
                    ].map((tool) => (
                      <View key={tool.label} style={styles.moreToolItem}>
                        <View style={styles.moreToolIcon}>
                          <Ionicons
                            name={tool.icon as any}
                            size={20}
                            color={THEME.accent}
                          />
                        </View>
                        <Text style={styles.moreToolLabel}>
                          {tool.label}
                        </Text>
                        <Text style={styles.moreToolDesc}>
                          {tool.desc}
                        </Text>
                      </View>
                    ))}
                  </View>
                </GlassCard>
              </Animated.View>
            )}

            {suggestions.length === 0 && !isGenerating && (
              <View style={styles.emptyCreate}>
                <View style={styles.emptyIconContainer}>
                  <LinearGradient
                    colors={[THEME.accentGlow, "transparent"]}
                    style={StyleSheet.absoluteFill}
                  />
                  <Ionicons name="bulb-outline" size={48} color={THEME.accent} />
                </View>
                <Text style={styles.emptyTitle}>
                  Create with AI assistance
                </Text>
                <Text style={styles.emptySubtext}>
                  Enter a topic above to get AI-powered title suggestions,
                  content strategies, and optimization tips.
                </Text>
              </View>
            )}
          </View>
        )}

        {activeTab === "trends" && (
          <View>
            <Text style={styles.sectionTitle}>
              Trending Topics
            </Text>
            <Text style={styles.sectionSubtitle}>
              AI-analyzed trends across the platform in real time
            </Text>
            {trendingTopics.map((topic) => (
              <TrendCard key={topic.id} topic={topic} />
            ))}
          </View>
        )}

        {activeTab === "insights" && (
          <View>
            <GlassCard style={styles.insightsSummary} accentGlow>
              <View style={styles.summaryRow}>
                <View style={styles.summaryItem}>
                  <Text style={styles.summaryValue}>12.4K</Text>
                  <Text style={styles.summaryLabel}>Total Views</Text>
                </View>
                <View style={styles.summaryDivider} />
                <View style={styles.summaryItem}>
                  <Text style={styles.summaryValue}>847</Text>
                  <Text style={styles.summaryLabel}>New Subs</Text>
                </View>
                <View style={styles.summaryDivider} />
                <View style={styles.summaryItem}>
                  <Text style={styles.summaryValue}>6.8%</Text>
                  <Text style={styles.summaryLabel}>Engage</Text>
                </View>
              </View>
            </GlassCard>

            <Text style={styles.sectionTitle}>
              AI-Powered Insights
            </Text>
            <Text style={styles.sectionSubtitle}>
              Personalized recommendations based on your channel analytics
            </Text>
            {creatorInsights.map((insight) => (
              <InsightCard key={insight.id} insight={insight} />
            ))}
          </View>
        )}

        <View style={{ height: 120 }} />
      </ScrollView>
      )}
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: THEME.bgPrimary,
  },
  header: {
    overflow: "hidden",
  },
  headerContent: {
    paddingHorizontal: 16,
    paddingTop: 14,
    paddingBottom: 8,
  },
  headerTitleRow: {
    flexDirection: "row",
    alignItems: "center",
    gap: 12,
  },
  aiIcon: {
    width: 36,
    height: 36,
    borderRadius: 12,
    backgroundColor: THEME.accent,
    justifyContent: "center",
    alignItems: "center",
    shadowColor: THEME.accent,
    shadowOffset: { width: 0, height: 0 },
    shadowOpacity: 0.5,
    shadowRadius: 12,
  },
  headerTitle: {
    color: THEME.textPrimary,
    fontSize: 22,
    fontWeight: "700",
    letterSpacing: -0.3,
  },
  headerSubtitle: {
    color: THEME.textSecondary,
    fontSize: 12,
    marginTop: 1,
  },
  tabRow: {
    flexDirection: "row",
    paddingHorizontal: 12,
    paddingBottom: 10,
    paddingTop: 6,
    gap: 6,
  },
  tabBtn: {
    flex: 1,
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "center",
    gap: 6,
    paddingVertical: 8,
    borderRadius: 10,
    backgroundColor: THEME.bgTertiary,
  },
  tabBtnActive: {
    backgroundColor: "rgba(255,68,68,0.15)",
    borderWidth: 1,
    borderColor: "rgba(255,68,68,0.3)",
  },
  tabText: {
    color: THEME.textSecondary,
    fontSize: 13,
    fontWeight: "500",
  },
  tabTextActive: {
    color: THEME.accent,
    fontWeight: "600",
  },
  scrollContent: {
    paddingHorizontal: 16,
    paddingTop: 16,
  },
  inputCard: {
    marginBottom: 20,
  },
  inputLabel: {
    color: THEME.textPrimary,
    fontSize: 16,
    fontWeight: "600",
    marginBottom: 12,
  },
  inputRow: {
    flexDirection: "row",
    gap: 10,
  },
  textInput: {
    flex: 1,
    height: 44,
    backgroundColor: "rgba(255,255,255,0.06)",
    borderRadius: 12,
    paddingHorizontal: 14,
    color: THEME.textPrimary,
    fontSize: 15,
    borderWidth: 1,
    borderColor: "rgba(255,255,255,0.08)",
  },
  generateBtn: {
    width: 44,
    height: 44,
    borderRadius: 12,
    backgroundColor: THEME.accent,
    justifyContent: "center",
    alignItems: "center",
    shadowColor: THEME.accent,
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.4,
    shadowRadius: 8,
  },
  generateBtnDisabled: {
    opacity: 0.4,
  },
  loadingContainer: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "center",
    gap: 10,
    paddingVertical: 24,
  },
  loadingDot: {
    width: 8,
    height: 8,
    borderRadius: 4,
    backgroundColor: THEME.accent,
  },
  loadingText: {
    color: THEME.textSecondary,
    fontSize: 14,
  },
  sectionTitle: {
    color: THEME.textPrimary,
    fontSize: 18,
    fontWeight: "700",
    marginBottom: 4,
  },
  sectionSubtitle: {
    color: THEME.textSecondary,
    fontSize: 13,
    marginBottom: 16,
    lineHeight: 18,
  },
  suggestionCard: {},
  suggestionHeader: {
    flexDirection: "row",
    alignItems: "flex-start",
    gap: 10,
  },
  suggestionRank: {
    width: 26,
    height: 26,
    borderRadius: 13,
    backgroundColor: "rgba(255,68,68,0.15)",
    justifyContent: "center",
    alignItems: "center",
  },
  suggestionRankText: {
    color: THEME.accent,
    fontSize: 13,
    fontWeight: "700",
  },
  suggestionTitle: {
    color: THEME.textPrimary,
    fontSize: 15,
    fontWeight: "600",
    lineHeight: 21,
  },
  copyBtn: {
    width: 36,
    height: 36,
    borderRadius: 18,
    justifyContent: "center",
    alignItems: "center",
    backgroundColor: "rgba(255,255,255,0.05)",
  },
  suggestionReasoning: {
    color: THEME.textSecondary,
    fontSize: 12,
    lineHeight: 17,
    marginTop: 8,
    paddingLeft: 36,
  },
  confidenceRow: {
    flexDirection: "row",
    justifyContent: "space-between",
    alignItems: "center",
    marginTop: 8,
    paddingLeft: 36,
  },
  confidenceLabel: {
    color: THEME.textSecondary,
    fontSize: 11,
  },
  confidenceValue: {
    color: THEME.textPrimary,
    fontSize: 11,
    fontWeight: "600",
  },
  moreToolsCard: {
    marginTop: 8,
  },
  moreToolsTitle: {
    color: THEME.textPrimary,
    fontSize: 15,
    fontWeight: "600",
    marginBottom: 14,
  },
  moreToolsGrid: {
    flexDirection: "row",
    flexWrap: "wrap",
    gap: 12,
  },
  moreToolItem: {
    width: (SCREEN_WIDTH - 32 - 32 - 12) / 2,
    alignItems: "center",
    gap: 6,
    paddingVertical: 12,
    backgroundColor: "rgba(255,255,255,0.03)",
    borderRadius: 12,
    borderWidth: 1,
    borderColor: "rgba(255,255,255,0.05)",
  },
  moreToolIcon: {
    width: 40,
    height: 40,
    borderRadius: 12,
    backgroundColor: "rgba(255,68,68,0.1)",
    justifyContent: "center",
    alignItems: "center",
  },
  moreToolLabel: {
    color: THEME.textPrimary,
    fontSize: 13,
    fontWeight: "600",
  },
  moreToolDesc: {
    color: THEME.textSecondary,
    fontSize: 11,
  },
  emptyCreate: {
    alignItems: "center",
    paddingTop: 40,
    gap: 16,
  },
  emptyIconContainer: {
    width: 96,
    height: 96,
    borderRadius: 48,
    justifyContent: "center",
    alignItems: "center",
    overflow: "hidden",
    backgroundColor: THEME.bgTertiary,
  },
  emptyTitle: {
    color: THEME.textPrimary,
    fontSize: 18,
    fontWeight: "600",
  },
  emptySubtext: {
    color: THEME.textSecondary,
    fontSize: 14,
    textAlign: "center",
    lineHeight: 20,
    paddingHorizontal: 24,
  },
  trendCard: {
    marginBottom: 14,
  },
  trendHeader: {},
  trendTitleRow: {
    flexDirection: "row",
    alignItems: "center",
    gap: 10,
  },
  trendIcon: {
    width: 32,
    height: 32,
    borderRadius: 10,
    backgroundColor: "rgba(52,211,153,0.12)",
    justifyContent: "center",
    alignItems: "center",
  },
  trendTitle: {
    color: THEME.textPrimary,
    fontSize: 15,
    fontWeight: "600",
  },
  trendCategory: {
    color: THEME.textSecondary,
    fontSize: 11,
    marginTop: 1,
  },
  growthBadge: {
    flexDirection: "row",
    alignItems: "center",
    gap: 3,
    backgroundColor: "rgba(52,211,153,0.12)",
    paddingHorizontal: 8,
    paddingVertical: 4,
    borderRadius: 8,
  },
  growthText: {
    color: THEME.success,
    fontSize: 12,
    fontWeight: "700",
  },
  trendAngle: {
    color: THEME.textSecondary,
    fontSize: 13,
    lineHeight: 18,
    marginTop: 10,
  },
  keywordsRow: {
    flexDirection: "row",
    gap: 8,
    marginTop: 10,
    flexWrap: "wrap",
  },
  keywordChip: {
    backgroundColor: "rgba(96,165,250,0.1)",
    paddingHorizontal: 10,
    paddingVertical: 4,
    borderRadius: 8,
  },
  keywordText: {
    color: THEME.info,
    fontSize: 12,
    fontWeight: "500",
  },
  insightsSummary: {
    marginBottom: 20,
  },
  summaryRow: {
    flexDirection: "row",
    alignItems: "center",
  },
  summaryItem: {
    flex: 1,
    alignItems: "center",
    gap: 4,
  },
  summaryValue: {
    color: THEME.textPrimary,
    fontSize: 22,
    fontWeight: "700",
  },
  summaryLabel: {
    color: THEME.textSecondary,
    fontSize: 11,
  },
  summaryDivider: {
    width: 1,
    height: 32,
    backgroundColor: "rgba(255,255,255,0.08)",
  },
  insightCard: {
    marginBottom: 12,
  },
  insightHeader: {
    flexDirection: "row",
    justifyContent: "space-between",
    alignItems: "center",
  },
  insightMetric: {
    color: THEME.textSecondary,
    fontSize: 13,
    fontWeight: "500",
  },
  insightBadge: {
    flexDirection: "row",
    alignItems: "center",
    gap: 4,
    paddingHorizontal: 8,
    paddingVertical: 3,
    borderRadius: 6,
  },
  insightChange: {
    fontSize: 12,
    fontWeight: "600",
  },
  insightValue: {
    color: THEME.textPrimary,
    fontSize: 28,
    fontWeight: "700",
    marginTop: 4,
  },
  insightDivider: {
    height: 1,
    backgroundColor: "rgba(255,255,255,0.06)",
    marginVertical: 10,
  },
  insightSuggestionRow: {
    flexDirection: "row",
    gap: 8,
    alignItems: "flex-start",
  },
  insightSuggestion: {
    flex: 1,
    color: THEME.textSecondary,
    fontSize: 12,
    lineHeight: 17,
  },
});
