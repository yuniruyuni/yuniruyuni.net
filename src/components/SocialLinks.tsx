import React from 'react';

export default function SocialLinks() {
  return (
    <div className="space-y-4">
      <a href="https://twitch.tv/yuniruyuni" className="block w-full md:w-auto bg-purple-600 hover:bg-purple-700 text-white font-bold py-2 px-4 rounded-full transition duration-300 ease-in-out">
        Twitch Channel (Main streaming)
      </a>
      <a href="https://youtube.com/@yuniruyuni" className="block w-full md:w-auto bg-pink-500 hover:bg-pink-600 text-white font-bold py-2 px-4 rounded-full transition duration-300 ease-in-out">
        Youtube Channel
      </a>
      <div className="w-full md:w-auto flex flex-row">
        <a href="https://twitter.com/yuniruyuni" className="w-full bg-blue-400 hover:bg-blue-500 text-white font-bold py-2 px-4 rounded-l-full border-r border border-dotted border-white transition duration-300 ease-in-out">
          Twitter(X)
        </a>
        <a href="https://twitter.com/hashtag/yunicode" className="relative w-fill bg-blue-400 hover:bg-blue-500 text-white font-bold py-2 px-4 border-r border border-dotted border-white transition duration-300 ease-in-out">
          <span className="absolute top-0 left-1 text-xs">Tag</span>
          <span className="text-sm">#yunicode</span>
        </a>
        <a href="https://twitter.com/hashtag/yunigraphics" className="relative flex-1 bg-blue-400 hover:bg-blue-500 text-white font-bold py-2 px-4 rounded-r-full transition duration-300 ease-in-out">
          <span className="absolute top-0 left-1 text-xs">FanArt</span>
          <span className="text-sm">#yunigraphics</span>
        </a>
      </div>
      <a href="https://github.com/yuniruyuni" className="block w-full md:w-auto bg-slate-400 hover:bg-slate-500 text-white font-bold py-2 px-4 rounded-full transition duration-300 ease-in-out">
        Github
      </a>
      <a href="https://costume.yuniruyuni.net/" className="block w-full md:w-auto bg-green-400 hover:bg-green-500 text-white font-bold py-2 px-4 rounded-full transition duration-300 ease-in-out">
        お着替えリスト
      </a>
      <a href="https://hari-stream.com/ja/mypage/USER205ST1334/" className="block w-full md:w-auto border bg-pink-300 hover:bg-pink-200 text-white font-bold py-2 px-4 rounded-full transition duration-300 ease-in-out">
        HARI(おたより/質問箱)
      </a>
    </div>
  );
}