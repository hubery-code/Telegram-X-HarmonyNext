/**
 * Telegram X HarmonyOS NEXT
 * GIF-101：GIF 动图模型与预置动图库（FEAT-P2-004）
 * 100% Kit-free 纯 ArkTS
 */

export interface GifItem {
  id: string;
  title: string;
  tag: string;
  category: string;
  fileId: number;
  width: number;
  height: number;
  duration: number;
  previewEmoji: string;
}

/** 预置 GIF 分类 */
export const GIF_CATEGORIES: string[] = [
  '🕒 Recent',
  '🔥 Trending',
  '😂 Funny',
  '🎉 Party',
  '❤️ Love',
  '🐱 Animals',
  '👏 Applause'
];

/** 预置初始最近使用 GIF 列表（4 项） */
export const DEFAULT_RECENT_GIFS: GifItem[] = [
  {
    id: 'gif_rec_1',
    title: 'Thumbs Up',
    tag: '#trending',
    category: '🔥 Trending',
    fileId: 2001,
    width: 320,
    height: 240,
    duration: 2,
    previewEmoji: '👍'
  },
  {
    id: 'gif_rec_2',
    title: 'Party Hard',
    tag: '#party',
    category: '🎉 Party',
    fileId: 2011,
    width: 320,
    height: 240,
    duration: 3,
    previewEmoji: '🎉'
  },
  {
    id: 'gif_rec_3',
    title: 'LOL Face',
    tag: '#funny',
    category: '😂 Funny',
    fileId: 2006,
    width: 320,
    height: 240,
    duration: 2,
    previewEmoji: '😂'
  },
  {
    id: 'gif_rec_4',
    title: 'Cat Vibe',
    tag: '#animals',
    category: '🐱 Animals',
    fileId: 2021,
    width: 320,
    height: 240,
    duration: 4,
    previewEmoji: '🐱'
  }
];

/** 预置各分类动图字典（fileId 2001 - 2040） */
export const DEFAULT_GIF_PACKS: Record<string, GifItem[]> = {
  '🔥 Trending': [
    { id: 'gif_t1', title: 'Thumbs Up', tag: '#trending', category: '🔥 Trending', fileId: 2001, width: 320, height: 240, duration: 2, previewEmoji: '👍' },
    { id: 'gif_t2', title: 'Fire Flame', tag: '#trending', category: '🔥 Trending', fileId: 2002, width: 320, height: 240, duration: 3, previewEmoji: '🔥' },
    { id: 'gif_t3', title: 'Mind Blown', tag: '#trending', category: '🔥 Trending', fileId: 2003, width: 320, height: 240, duration: 3, previewEmoji: '🤯' },
    { id: 'gif_t4', title: 'Cool Vibes', tag: '#trending', category: '🔥 Trending', fileId: 2004, width: 320, height: 240, duration: 2, previewEmoji: '😎' },
    { id: 'gif_t5', title: 'Victory Sign', tag: '#trending', category: '🔥 Trending', fileId: 2005, width: 320, height: 240, duration: 2, previewEmoji: '✌️' }
  ],
  '😂 Funny': [
    { id: 'gif_f1', title: 'LOL Face', tag: '#funny', category: '😂 Funny', fileId: 2006, width: 320, height: 240, duration: 2, previewEmoji: '😂' },
    { id: 'gif_f2', title: 'Rolling Floor', tag: '#funny', category: '😂 Funny', fileId: 2007, width: 320, height: 240, duration: 3, previewEmoji: '🤣' },
    { id: 'gif_f3', title: 'Silly Clown', tag: '#funny', category: '😂 Funny', fileId: 2008, width: 320, height: 240, duration: 2, previewEmoji: '🤡' },
    { id: 'gif_f4', title: 'Awkward Smile', tag: '#funny', category: '😂 Funny', fileId: 2009, width: 320, height: 240, duration: 2, previewEmoji: '😬' },
    { id: 'gif_f5', title: 'Sneaky Grin', tag: '#funny', category: '😂 Funny', fileId: 2010, width: 320, height: 240, duration: 2, previewEmoji: '😏' }
  ],
  '🎉 Party': [
    { id: 'gif_p1', title: 'Party Popper', tag: '#party', category: '🎉 Party', fileId: 2011, width: 320, height: 240, duration: 3, previewEmoji: '🎉' },
    { id: 'gif_p2', title: 'Dancing Queen', tag: '#party', category: '🎉 Party', fileId: 2012, width: 320, height: 240, duration: 4, previewEmoji: '💃' },
    { id: 'gif_p3', title: 'Disco Ball', tag: '#party', category: '🎉 Party', fileId: 2013, width: 320, height: 240, duration: 3, previewEmoji: '🪩' },
    { id: 'gif_p4', title: 'Cheers Drinks', tag: '#party', category: '🎉 Party', fileId: 2014, width: 320, height: 240, duration: 2, previewEmoji: '🥂' },
    { id: 'gif_p5', title: 'Confetti Rain', tag: '#party', category: '🎉 Party', fileId: 2015, width: 320, height: 240, duration: 3, previewEmoji: '🎊' }
  ],
  '❤️ Love': [
    { id: 'gif_l1', title: 'Sparkling Heart', tag: '#love', category: '❤️ Love', fileId: 2016, width: 320, height: 240, duration: 2, previewEmoji: '💖' },
    { id: 'gif_l2', title: 'Heart Eyes', tag: '#love', category: '❤️ Love', fileId: 2017, width: 320, height: 240, duration: 3, previewEmoji: '😍' },
    { id: 'gif_l3', title: 'Blowing Kiss', tag: '#love', category: '❤️ Love', fileId: 2018, width: 320, height: 240, duration: 2, previewEmoji: '😘' },
    { id: 'gif_l4', title: 'Red Rose', tag: '#love', category: '❤️ Love', fileId: 2019, width: 320, height: 240, duration: 3, previewEmoji: '🌹' },
    { id: 'gif_l5', title: 'Big Hug', tag: '#love', category: '❤️ Love', fileId: 2020, width: 320, height: 240, duration: 3, previewEmoji: '🤗' }
  ],
  '🐱 Animals': [
    { id: 'gif_a1', title: 'Cat Vibe', tag: '#animals', category: '🐱 Animals', fileId: 2021, width: 320, height: 240, duration: 4, previewEmoji: '🐱' },
    { id: 'gif_a2', title: 'Happy Doggy', tag: '#animals', category: '🐱 Animals', fileId: 2022, width: 320, height: 240, duration: 3, previewEmoji: '🐶' },
    { id: 'gif_a3', title: 'Panda Roll', tag: '#animals', category: '🐱 Animals', fileId: 2023, width: 320, height: 240, duration: 3, previewEmoji: '🐼' },
    { id: 'gif_a4', title: 'Bunny Hop', tag: '#animals', category: '🐱 Animals', fileId: 2024, width: 320, height: 240, duration: 2, previewEmoji: '🐰' },
    { id: 'gif_a5', title: 'Koala Nap', tag: '#animals', category: '🐱 Animals', fileId: 2025, width: 320, height: 240, duration: 4, previewEmoji: '🐨' }
  ],
  '👏 Applause': [
    { id: 'gif_ap1', title: 'Standing Ovation', tag: '#applause', category: '👏 Applause', fileId: 2026, width: 320, height: 240, duration: 3, previewEmoji: '👏' },
    { id: 'gif_ap2', title: 'Clap Clap', tag: '#applause', category: '👏 Applause', fileId: 2027, width: 320, height: 240, duration: 2, previewEmoji: '🙌' },
    { id: 'gif_ap3', title: 'Chef Kiss', tag: '#applause', category: '👏 Applause', fileId: 2028, width: 320, height: 240, duration: 3, previewEmoji: '👌' },
    { id: 'gif_ap4', title: 'Salute You', tag: '#applause', category: '👏 Applause', fileId: 2029, width: 320, height: 240, duration: 2, previewEmoji: '🫡' },
    { id: 'gif_ap5', title: 'Top Notch', tag: '#applause', category: '👏 Applause', fileId: 2030, width: 320, height: 240, duration: 2, previewEmoji: '💯' }
  ]
};
