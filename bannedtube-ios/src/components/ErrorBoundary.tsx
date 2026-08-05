import React, { Component, type ReactNode } from "react";
import { View, Text, TouchableOpacity, StyleSheet, ActivityIndicator } from "react-native";
import { Ionicons } from "@expo/vector-icons";

interface ErrorBoundaryProps {
  children: ReactNode;
}

interface ErrorBoundaryState {
  hasError: boolean;
  error: Error | null;
  reloading: boolean;
}

export default class ErrorBoundary extends Component<ErrorBoundaryProps, ErrorBoundaryState> {
  state: ErrorBoundaryState = {
    hasError: false,
    error: null,
    reloading: false,
  };

  static getDerivedStateFromError(error: Error): ErrorBoundaryState {
    return { hasError: true, error, reloading: false };
  }

  handleReload = () => {
    this.setState({ reloading: true });
    setTimeout(() => {
      this.setState({ hasError: false, error: null, reloading: false });
    }, 500);
  };

  render() {
    if (this.state.hasError) {
      return (
        <View style={styles.container}>
          <View style={styles.iconWrap}>
            <Ionicons name="warning" size={48} color="#ff4444" />
          </View>
          <Text style={styles.title}>Something went wrong</Text>
          <Text style={styles.subtitle}>
            BannedTube encountered an unexpected error. Your data is safe.
          </Text>
          {__DEV__ && this.state.error && (
            <Text style={styles.errorText} numberOfLines={10}>
              {this.state.error.message}
            </Text>
          )}
          <TouchableOpacity
            style={styles.retryBtn}
            onPress={this.handleReload}
            disabled={this.state.reloading}
            accessibilityRole="button"
            accessibilityLabel="Reload app"
          >
            {this.state.reloading ? (
              <ActivityIndicator color="#fff" size="small" />
            ) : (
              <Text style={styles.retryText}>Reload App</Text>
            )}
          </TouchableOpacity>
        </View>
      );
    }

    return this.props.children;
  }
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: "#0f0f0f",
    justifyContent: "center",
    alignItems: "center",
    paddingHorizontal: 32,
  },
  iconWrap: {
    width: 80,
    height: 80,
    borderRadius: 40,
    backgroundColor: "rgba(255,68,68,0.15)",
    justifyContent: "center",
    alignItems: "center",
    marginBottom: 20,
  },
  title: {
    color: "#f1f1f1",
    fontSize: 22,
    fontWeight: "700",
    marginBottom: 8,
  },
  subtitle: {
    color: "#aaaaaa",
    fontSize: 15,
    textAlign: "center",
    lineHeight: 21,
    marginBottom: 24,
  },
  errorText: {
    color: "#666",
    fontSize: 12,
    fontFamily: "monospace",
    marginBottom: 24,
    textAlign: "center",
  },
  retryBtn: {
    backgroundColor: "#ff4444",
    paddingHorizontal: 32,
    paddingVertical: 14,
    borderRadius: 24,
  },
  retryText: {
    color: "#fff",
    fontSize: 16,
    fontWeight: "700",
  },
});
