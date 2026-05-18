import * as admin from 'firebase-admin';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { defineSecret } from 'firebase-functions/params';

admin.initializeApp();

const db = admin.firestore();
const oneSignalAppId = defineSecret('ONESIGNAL_APP_ID');
const oneSignalRestApiKey = defineSecret('ONESIGNAL_REST_API_KEY');

const SCHEDULE = 'every day 09:00';
const TIME_ZONE = 'Europe/Paris';
const POPULAR_POST_LOOKBACK_DAYS = 7;
const MIN_POPULAR_SCORE = 3;

type NotificationPrefs = Record<string, boolean>;

type UserDoc = {
  username?: string;
  name?: string;
  oneSignalPlayerId?: string;
  notificationPrefs?: NotificationPrefs;
};

type JourneeDoc = {
  userId?: string;
  date?: admin.firestore.Timestamp;
  reactions?: Record<string, unknown>;
  texte1?: string | null;
  commentaire?: string | null;
  photoUrls?: string[];
};

type FriendshipGraph = Map<string, Set<string>>;

type PopularPost = {
  id: string;
  authorId: string;
  authorName: string;
  score: number;
  date: Date;
  summary: string;
};

type Recommendation = {
  id: string;
  username: string;
  score: number;
};

function hasNotificationEnabled(user: UserDoc, key: string): boolean {
  return user.notificationPrefs?.[key] ?? true;
}

function getUserDisplayName(user: UserDoc, fallback = 'Quelqu\'un'): string {
  return user.username?.trim() || user.name?.trim() || fallback;
}

function getReactionScore(reactions?: Record<string, unknown>): number {
  if (!reactions) return 0;

  return Object.values(reactions).reduce<number>((total, value) => {
    if (Array.isArray(value)) {
      return total + value.length;
    }
    return total;
  }, 0);
}

function buildDayRangeFromDate(referenceDate: Date): { start: Date; end: Date } {
  const start = new Date(referenceDate);
  start.setHours(0, 0, 0, 0);
  const end = new Date(start);
  end.setDate(end.getDate() + 1);
  return { start, end };
}

function formatDateLabel(date: Date): string {
  return new Intl.DateTimeFormat('fr-FR', {
    day: '2-digit',
    month: 'long',
    year: 'numeric',
  }).format(date);
}

function buildExcerpt(text: string | null | undefined): string {
  const cleanText = (text ?? '').trim().replace(/\s+/g, ' ');
  if (!cleanText) {
    return '';
  }
  return cleanText.length > 120 ? `${cleanText.slice(0, 117)}...` : cleanText;
}

async function sendOneSignalNotification(params: {
  playerId: string;
  title: string;
  message: string;
  data?: Record<string, string>;
}): Promise<void> {
  const { playerId, title, message, data } = params;

  const response = await fetch('https://onesignal.com/api/v1/notifications', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json; charset=UTF-8',
      Authorization: `Basic ${oneSignalRestApiKey.value()}`,
    },
    body: JSON.stringify({
      app_id: oneSignalAppId.value(),
      include_player_ids: [playerId],
      headings: { fr: title, en: title },
      contents: { fr: message, en: message },
      data: data ?? {},
    }),
  });

  if (!response.ok) {
    const errorBody = await response.text();
    throw new Error(`OneSignal error ${response.status}: ${errorBody}`);
  }
}

async function loadUsers(): Promise<Array<{ id: string; data: UserDoc }>> {
  const snapshot = await db.collection('users').get();
  return snapshot.docs.map((doc) => ({
    id: doc.id,
    data: doc.data() as UserDoc,
  }));
}

async function loadFriendshipGraph(): Promise<FriendshipGraph> {
  const snapshot = await db.collection('friends').get();
  const graph: FriendshipGraph = new Map();

  for (const doc of snapshot.docs) {
    const users = doc.get('users');
    if (!Array.isArray(users) || users.length < 2) {
      continue;
    }

    const [firstUser, secondUser] = users.map((user) => String(user));
    if (!graph.has(firstUser)) graph.set(firstUser, new Set());
    if (!graph.has(secondUser)) graph.set(secondUser, new Set());

    graph.get(firstUser)!.add(secondUser);
    graph.get(secondUser)!.add(firstUser);
  }

  return graph;
}

async function findMemoriesForUser(userId: string): Promise<admin.firestore.QueryDocumentSnapshot | null> {
  const now = new Date();
  const referenceDate = new Date(now);
  referenceDate.setFullYear(referenceDate.getFullYear() - 1);
  const { start, end } = buildDayRangeFromDate(referenceDate);

  const snapshot = await db
    .collection('journees')
    .where('userId', '==', userId)
    .where('date', '>=', admin.firestore.Timestamp.fromDate(start))
    .where('date', '<', admin.firestore.Timestamp.fromDate(end))
    .orderBy('date', 'desc')
    .limit(1)
    .get();

  return snapshot.docs[0] ?? null;
}

async function buildPopularPostsByAuthor(): Promise<Map<string, PopularPost>> {
  const snapshot = await db
    .collection('journees')
    .orderBy('date', 'desc')
    .limit(200)
    .get();

  const cutoff = Date.now() - POPULAR_POST_LOOKBACK_DAYS * 24 * 60 * 60 * 1000;
  const authors = new Map<string, PopularPost>();

  for (const doc of snapshot.docs) {
    const data = doc.data() as JourneeDoc;
    const date = data.date?.toDate();
    if (!date || date.getTime() < cutoff) {
      continue;
    }

    const authorId = data.userId;
    if (!authorId) {
      continue;
    }

    const score = getReactionScore(data.reactions);
    const summary = buildExcerpt(data.texte1 ?? data.commentaire);

    const existing = authors.get(authorId);
    if (!existing || score > existing.score || (score === existing.score && date > existing.date)) {
      authors.set(authorId, {
        id: doc.id,
        authorId,
        authorName: '',
        score,
        date,
        summary,
      });
    }
  }

  return authors;
}

function buildFriendRecommendations(graph: FriendshipGraph, userId: string): Recommendation[] {
  const directFriends = graph.get(userId) ?? new Set<string>();
  const candidateScores = new Map<string, number>();

  for (const directFriendId of directFriends) {
    const friendsOfFriend = graph.get(directFriendId);
    if (!friendsOfFriend) continue;

    for (const candidateId of friendsOfFriend) {
      if (candidateId === userId || directFriends.has(candidateId)) {
        continue;
      }
      candidateScores.set(candidateId, (candidateScores.get(candidateId) ?? 0) + 1);
    }
  }

  return [...candidateScores.entries()]
    .map(([id, score]) => ({ id, score, username: '' }))
    .sort((a, b) => b.score - a.score || a.id.localeCompare(b.id))
    .slice(0, 3);
}

async function notifyMemories(): Promise<void> {
  const users = await loadUsers();

  for (const user of users) {
    if (!hasNotificationEnabled(user.data, 'memories')) {
      continue;
    }

    const playerId = user.data.oneSignalPlayerId;
    if (!playerId) {
      continue;
    }

    const memoryJournee = await findMemoriesForUser(user.id);
    if (!memoryJournee) {
      continue;
    }

    const journeeData = memoryJournee.data() as JourneeDoc;
    const journeeDate = journeeData.date?.toDate();
    const dateLabel = journeeDate ? formatDateLabel(journeeDate) : 'il y a un an';
    const excerpt = buildExcerpt(journeeData.texte1 ?? journeeData.commentaire);
    const message = excerpt
      ? `Il y a 1 an (${dateLabel}), vous aviez partagé: ${excerpt}`
      : `Il y a 1 an (${dateLabel}), vous aviez partagé une journée.`;

    await sendOneSignalNotification({
      playerId,
      title: 'Memories - Ce jour-là',
      message,
      data: {
        type: 'memories',
        journeeId: memoryJournee.id,
      },
    });
  }
}

async function notifyPopularPosts(): Promise<void> {
  const users = await loadUsers();
  const popularPostsByAuthor = await buildPopularPostsByAuthor();
  const graph = await loadFriendshipGraph();

  if (popularPostsByAuthor.size === 0) {
    return;
  }

  const authorIds = [...popularPostsByAuthor.keys()];
  const authorDocs = await Promise.all(
    authorIds.map(async (authorId) => {
      const doc = await db.collection('users').doc(authorId).get();
      return {
        id: authorId,
        data: (doc.data() as UserDoc | undefined) ?? {},
      };
    }),
  );

  const authorNames = new Map(authorDocs.map((entry) => [entry.id, getUserDisplayName(entry.data)]));
  for (const [authorId, popularPost] of popularPostsByAuthor.entries()) {
    popularPost.authorName = authorNames.get(authorId) ?? 'Un ami';
  }

  for (const user of users) {
    if (!hasNotificationEnabled(user.data, 'post_populaire')) {
      continue;
    }

    const playerId = user.data.oneSignalPlayerId;
    if (!playerId) {
      continue;
    }

    const directFriends = graph.get(user.id) ?? new Set<string>();
    if (directFriends.size === 0) {
      continue;
    }

    let bestPost: PopularPost | null = null;
    for (const friendId of directFriends) {
      const friendPost = popularPostsByAuthor.get(friendId);
      if (!friendPost) continue;

      if (!bestPost || friendPost.score > bestPost.score) {
        bestPost = friendPost;
      }
    }

    if (!bestPost || bestPost.score < MIN_POPULAR_SCORE) {
      continue;
    }

    const message = bestPost.summary
      ? `${bestPost.authorName} fait parler de lui avec ${bestPost.score} réactions: ${bestPost.summary}`
      : `${bestPost.authorName} fait parler de lui avec ${bestPost.score} réactions.`;

    await sendOneSignalNotification({
      playerId,
      title: 'Post populaire chez vos amis',
      message,
      data: {
        type: 'post_populaire',
        journeeId: bestPost.id,
        authorId: bestPost.authorId,
      },
    });
  }
}

async function notifyRecommendations(): Promise<void> {
  const users = await loadUsers();
  const graph = await loadFriendshipGraph();

  for (const user of users) {
    if (!hasNotificationEnabled(user.data, 'recommandations')) {
      continue;
    }

    const playerId = user.data.oneSignalPlayerId;
    if (!playerId) {
      continue;
    }

    const directFriends = graph.get(user.id) ?? new Set<string>();
    if (directFriends.size === 0) {
      continue;
    }

    const recommendations = buildFriendRecommendations(graph, user.id);
    if (recommendations.length === 0) {
      continue;
    }

    const topRecommendationIds = recommendations.map((item) => item.id);
    const recommendedUsers = await Promise.all(
      topRecommendationIds.map(async (recommendedId) => {
        const doc = await db.collection('users').doc(recommendedId).get();
        return {
          id: recommendedId,
          data: (doc.data() as UserDoc | undefined) ?? {},
        };
      }),
    );

    const topNames = recommendedUsers
      .map((entry) => getUserDisplayName(entry.data, 'Un ami'))
      .slice(0, 3);

    await sendOneSignalNotification({
      playerId,
      title: 'Recommandations d\'amis',
      message: `Vous pourriez connaître ${topNames.join(', ')}.`,
      data: {
        type: 'recommandations',
        suggestions: topRecommendationIds.join(','),
      },
    });
  }
}

export const sendMemoriesNotifications = onSchedule(
  {
    schedule: SCHEDULE,
    timeZone: TIME_ZONE,
    secrets: [oneSignalAppId, oneSignalRestApiKey],
  },
  async () => {
    await notifyMemories();
  },
);

export const sendPopularPostNotifications = onSchedule(
  {
    schedule: SCHEDULE,
    timeZone: TIME_ZONE,
    secrets: [oneSignalAppId, oneSignalRestApiKey],
  },
  async () => {
    await notifyPopularPosts();
  },
);

export const sendRecommendationNotifications = onSchedule(
  {
    schedule: SCHEDULE,
    timeZone: TIME_ZONE,
    secrets: [oneSignalAppId, oneSignalRestApiKey],
  },
  async () => {
    await notifyRecommendations();
  },
);
