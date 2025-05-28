import React from 'react';

export default function TwitterLinkGroup() {
  return (
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
  );
}