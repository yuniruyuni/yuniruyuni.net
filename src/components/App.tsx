import React from 'react';

export default function App() {

  return (
    <div className="min-h-screen">
      <div className="h-screen flex justify-center items-center">
        <img className="-z-10 fixed w-full h-screen top-0 left-0 object-cover lg:object-scale-down object-top" src="top.webp" alt="ゆにるユニ" />
        <h1 className="relative text-white text-center">yuniruyuni.net</h1>
      </div>

      <div id="content" className="container mx-auto px-4">
        <div className="bg-white bg-opacity-90 rounded-xl shadow-2xl p-8 max-w-4xl mx-auto">
          <header className="text-center mb-8">
            <h2 className="text-4xl font-bold text-purple-800 mb-2">ゆにるユニ</h2>
            <p className="text-xl text-gray-600">2222年からやってきた未来のVirtual TechLead</p>
            <p className="text-xl text-gray-600">ところが実際には遊んでばかり！？</p>
          </header>

          <div className="flex flex-col md:flex-row items-center justify-between">
            <div className="md:w-1/2 mb-8 md:mb-0">
              <img src="stand.webp" alt="立ち絵" className="rounded-lg mx-auto" />
            </div>
            <div className="md:w-1/2 text-center md:text-left">
              <p className="text-lg text-gray-700 mb-2">IT技術のお話やプログラミングの配信を中心に、ゲーム遊んだり歌やピアノなどのやったことのない新しいスキルを身に着ける挑戦をしてみたり、色々と活動しています✨</p>
              <p className="text-lg text-gray-700 mb-2">個人勢のVStreamerです🌟2022.2.4 Debut✨</p>
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
            </div>
          </div>
        </div>

        <div className="bg-white bg-opacity-90 rounded-xl shadow-2xl p-8 max-w-4xl mx-auto my-16">
          <header className="text-center mb-8">
            <h2 className="text-2xl font-bold text-gray-600 mb-2">📚二次創作・ファンアートについて</h2>
          </header>

          <ul className="md:w-full text-center md:text-left list-outside list-disc">
            <li className="text-gray-600">私のアバターはHoneycrisp様の<a href="https://booth.pm/ja/items/2198694" className="font-medium text-blue-600 underline dark:text-blue-500 hover:no-underline">ユキちゃん</a>です。</li>
            <li className="text-gray-600">そのため私は一次創作者ではないのです…<span className="font-bold">が、</span></li>
            <li className="text-gray-600">Honeycrisp様に私(ゆにるユニ)の二次創作を誰でもやってよいという許可をいただいています✨</li>
            <li className="text-gray-600 font-bold">そのためイラスト化やマンガ化といった二次創作、大歓迎です！</li>
            <li className="text-gray-600">ただし他のユキちゃんとの区別として髪の色を水色にするか、胸元に時計を持たせてください。</li>
            <li className="text-gray-600">またR18指定が必要なものについては、NSFW表示など未成年の視聴者への配慮を各々でお願いいたします。</li>
            <li className="text-gray-600">宜しければ配信のサムネイルや SNS投稿に使用する可能性があることを了承の上 <a href="https://x.com/hashtag/yunigraphics" className="font-medium text-blue-600 underline dark:text-blue-500 hover:no-underline">#yunigraphics</a> のタグ付きで投稿していただけると嬉しいです。</li>
            <li className="text-gray-600 font-bold">この件については、ご迷惑になるのでHoneycrisp様に問い合わせるのはやめてください。</li>
          </ul>
        </div>
      </div>
    </div>
  );
}