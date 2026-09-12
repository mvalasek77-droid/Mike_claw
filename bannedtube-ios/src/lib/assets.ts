import { ImageSourcePropType } from "react-native";

/**
 * Bundled artwork, keyed by the id of the thing it belongs to.
 *
 * Both maps are intentionally empty. The app previously shipped generated
 * placeholder art for videos and channels that did not exist; that has been
 * removed rather than passed off as real content. Components fall back to the
 * gradient placeholder whenever a lookup misses, so leaving these empty is safe.
 *
 * To add real artwork:
 *   1. Drop the files in `assets/thumbnails/` and `assets/avatars/`.
 *   2. Add an entry below keyed by `Video.id` / `Channel.id` from `data.ts`,
 *      e.g. `"sintel": require("../../assets/thumbnails/sintel.jpg"),`
 *
 * Thumbnails look best at 1280x720; avatars at 400x400.
 */

export const thumbnails: Record<string, ImageSourcePropType> = {};

export const avatars: Record<string, ImageSourcePropType> = {};
