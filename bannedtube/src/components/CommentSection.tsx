"use client";

import { useState } from "react";
import { ThumbsUp, ChevronDown, ChevronUp } from "lucide-react";
import { getComments, type Comment } from "@/lib/data";

function CommentItem({ comment }: { comment: Comment }) {
  const [showReplies, setShowReplies] = useState(false);

  return (
    <div className="flex gap-3 mb-5">
      <img
        src={comment.avatar}
        alt={comment.author}
        className="w-10 h-10 rounded-full flex-shrink-0"
      />
      <div className="flex-1">
        <div className="flex items-center gap-2 mb-1">
          <span className="text-sm font-medium">{comment.author}</span>
          <span className="text-xs text-[var(--text-secondary)]">
            {comment.timeAgo}
          </span>
        </div>
        <p className="text-sm text-[var(--text-primary)] mb-2">
          {comment.text}
        </p>
        <div className="flex items-center gap-4">
          <button className="flex items-center gap-1 text-xs text-[var(--text-secondary)] hover:text-[var(--text-primary)]">
            <ThumbsUp size={14} />
            {comment.likes.toLocaleString()}
          </button>
          {comment.replies && comment.replies.length > 0 && (
            <button
              onClick={() => setShowReplies(!showReplies)}
              className="flex items-center gap-1 text-xs text-blue-400 font-medium"
            >
              {showReplies ? (
                <ChevronUp size={14} />
              ) : (
                <ChevronDown size={14} />
              )}
              {comment.replies.length}{" "}
              {comment.replies.length === 1 ? "reply" : "replies"}
            </button>
          )}
        </div>
        {showReplies && comment.replies && (
          <div className="mt-3 ml-2 border-l-2 border-[var(--border)] pl-4">
            {comment.replies.map((reply) => (
              <CommentItem key={reply.id} comment={reply} />
            ))}
          </div>
        )}
      </div>
    </div>
  );
}

export default function CommentSection() {
  const comments = getComments();
  const [commentText, setCommentText] = useState("");

  return (
    <div className="mt-6">
      <h3 className="text-base font-medium mb-6">
        {comments.length} Comments
      </h3>

      <div className="flex gap-3 mb-8">
        <div className="w-10 h-10 rounded-full bg-purple-600 flex items-center justify-center flex-shrink-0">
          <span className="text-white text-sm font-medium">Y</span>
        </div>
        <div className="flex-1">
          <input
            type="text"
            placeholder="Add a comment..."
            value={commentText}
            onChange={(e) => setCommentText(e.target.value)}
            className="w-full bg-transparent border-b border-[var(--border)] py-2 text-sm outline-none focus:border-[var(--text-primary)] transition-colors placeholder:text-[var(--text-secondary)]"
          />
          {commentText && (
            <div className="flex justify-end gap-2 mt-2">
              <button
                onClick={() => setCommentText("")}
                className="px-4 py-2 text-sm rounded-full hover:bg-[var(--bg-tertiary)]"
              >
                Cancel
              </button>
              <button className="px-4 py-2 text-sm rounded-full bg-[var(--accent)] text-white hover:bg-[var(--accent-hover)]">
                Comment
              </button>
            </div>
          )}
        </div>
      </div>

      <div>
        {comments.map((comment) => (
          <CommentItem key={comment.id} comment={comment} />
        ))}
      </div>
    </div>
  );
}
