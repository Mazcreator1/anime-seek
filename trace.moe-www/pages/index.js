import { useEffect, useState } from "react";

import Head from "next/head";

import Layout from "../components/layout";

import Result from "../components/result";

import Player from "../components/player";

import Info from "../components/info";
import LegalPage from "../components/legalpage";
import SearchBar from "../components/search-bar";
import Link from "next/link";
import {

  dropTarget,

  dropping,

  main,

  mainReady,

  searchImageDisplay,

  messageTextLabel,

  detail,

  originalImageDisplay,

  resultList,

  wrap,

  playerInfoPane,

  hidden,

  closeBtn,

} from "../components/index.module.css";



const NEXT_PUBLIC_API_ENDPOINT = process.env.NEXT_PUBLIC_API_ENDPOINT;

const SURFACE = "#22242A";

const TEXT = "#FFFFFF";



const Index = () => {

  const [dropTargetText, setDropTargetText] = useState("");

  const [isCutBorders, setIsCutBorders] = useState(true);

  const [anilistFilter, setAnilistFilter] = useState();

  const [messageText, setMessageText] = useState("");

  const [imageURL, setImageURL] = useState("");

  const [searchImage, setSearchImage] = useState("");

  const [searchImageSrc, setSearchImageSrc] = useState("");

  const [searchResults, setSearchResults] = useState([]);

  const [selectedResult, setSelectedResult] = useState();

  const [showNSFW, setshowNSFW] = useState(false);

  const [anilistInfo, setAnilistInfo] = useState();

  const [playerSrc, setPlayerSrc] = useState();

  const [playerTimeCode, setPlayerTimeCode] = useState("");

  const [playerFileName, setPlayerFileName] = useState("");

  const [isLoading, setIsLoading] = useState(false);

  const [isSearching, setIsSearching] = useState(false);



  useEffect(() => {

    const searchParams = new URLSearchParams(location.search);

    if (searchParams.has("url")) {

      setImageURL(searchParams.get("url"));

      setSearchImageSrc(

        searchParams.get("url").startsWith(location.origin)

          ? searchParams.get("url")

          : `/image-proxy?url=${encodeURIComponent(searchParams.get("url"))}`

      );

    }

    const onPaste = (e) => {

      const items = e.clipboardData && e.clipboardData.items;

      if (!items) return;

      const item = Array.from(items).find((it) => it.type.startsWith("image"));

      if (!item) return;

      const file = item.getAsFile();

      if (file) {

        setSearchImageSrc(URL.createObjectURL(file));

        e.preventDefault();

      }

    };

    document.addEventListener("paste", onPaste, false);



    window.onerror = function (message, _source, _lineno, _colno, error) {

      if (typeof window.ga === "function") {

        window.ga("send", "event", "error", error ? error.stack : message);

      }

    };



    return () => document.removeEventListener("paste", onPaste, false);

  }, []);



  const imageURLInput = (e) => {

    e.preventDefault();

    if (!e.target.value.length) {

      setImageURL("");

      history.replaceState(null, "", "/");

      return;

    }

    if (e.target.parentNode.checkValidity()) {

      setImageURL(e.target.value);

      setSearchImageSrc(`/image-proxy?url=${encodeURIComponent(e.target.value)}`);

      history.replaceState(null, "", `/?url=${encodeURIComponent(e.target.value)}`);

    } else {

      const submit = e.target.parentNode.querySelector("input[type=submit]");

      if (submit) submit.click();

    }

  };



  const handleFileSelect = function (e) {

    e.stopPropagation();

    e.preventDefault();

    if (imageURL) {

      setImageURL("");

      history.replaceState(null, "", "/");

    }

    const file = e.dataTransfer ? e.dataTransfer.files[0] : e.target.files[0];

    if (!file || !file.type.match("image.*")) {

      setDropTargetText("Error: File is not an image");

      return "Error: File is not an image";

    }

    setDropTargetText("");

    e.target.classList.remove(dropping);

    setSearchImageSrc(URL.createObjectURL(file));

    return "";

  };



  useEffect(() => {

    if (!searchImageSrc) return;

    setIsLoading(true);

    setMessageText("Loading search image...");

    const image = new Image();

    image.onload = (ev) => {

      const img = ev.target;

      const canvas = document.createElement("canvas");

      const ctx = canvas.getContext("2d");

      if (!ctx) return;



      if (img.width <= 640 && img.height <= 640) {

        canvas.width = img.width;

        canvas.height = img.height;

      } else if (img.width > img.height) {

        canvas.width = 640;

        canvas.height = 640 * (img.height / img.width);

      } else {

        canvas.width = 640 * (img.width / img.height);

        canvas.height = 640;

      }

      ctx.drawImage(img, 0, 0, img.width, img.height, 0, 0, canvas.width, canvas.height);

      canvas.toBlob(function (blob) {

        setIsLoading(false);

        setSearchImage(blob);

        search(blob);

      }, "image/jpeg", 0.8);

    };

    image.onerror = () => setMessageText("Failed to load search image");

    image.src = searchImageSrc;

  }, [searchImageSrc]);



  // Make "~99.xx% Similarity" white only.

  useEffect(() => {

    const root = document.getElementById("appRoot");

    if (!root) return;

    const nodes = root.querySelectorAll(`.${resultList} *`);

    nodes.forEach((el) => {

      const t = (el.textContent || "").trim();

      if (/~\s*\d+(\.\d+)?%?\s*Similarity/i.test(t)) {

        el.style.color = "#FFFFFF";

      }

    });

  }, [searchResults, selectedResult]);



  const search = async (imageBlob) => {

    setMessageText("Searching...");

    setSearchResults([]);

    setSelectedResult(undefined);

    setAnilistInfo(undefined);

    setPlayerSrc(undefined);

    setPlayerFileName("");

    setPlayerTimeCode("");

    setIsSearching(true);

    const startSearchTime = performance.now();

    const buildFormData = () => {
      const formData = new FormData();
      formData.append("image", imageBlob);
      return formData;
    };

    const queryString = [

      "anilistInfo=1",

      isCutBorders ? "cutBorders" : "",

      anilistFilter ? `anilistID=${anilistFilter}` : ""

    ].filter(Boolean).join("&");

    const tryEndpoint = async (path) => {
      return fetch(`${NEXT_PUBLIC_API_ENDPOINT}${path}?${queryString}`, {
        method: "POST",
        body: buildFormData(),
        headers: { "x-debug": "1" }
      });
    };

    let res = await tryEndpoint("/search");

    const contentType = res.headers.get("content-type") || "";
    const looksLikeHtml = contentType.includes("text/html");

    if (res.status === 404 || looksLikeHtml) {
      try {
        const clone = res.clone();
        const text = await clone.text();
        const fallbackDetected =
          looksLikeHtml ||
          text.includes("Cannot POST /search") ||
          text.includes("ENOENT") ||
          text.includes("index.html");

        if (fallbackDetected) {
          console.warn("Primary /search failed or hit frontend fallback. Retrying /api/search");
          res = await tryEndpoint("/api/search");
        }
      } catch {
        res = await tryEndpoint("/api/search");
      }
    }

    setIsSearching(false);



    if (res.status === 429) {

      setMessageText("You searched too many times, please try again later.");

      return;

    }

    if (res.status === 503) {

      for (let i = 5; i > 0; i--) {

        setMessageText(`Server is busy, retrying in ${i}s`);

        await new Promise((resolve) => setTimeout(resolve, 1000));

      }

      search(imageBlob);

      return;

    }

    if (res.status >= 400) {

      let msg = "Unexpected error. Please try again later.";

      try {

        const j = await res.json();

        msg = j.error || j.message || msg;

      } catch {}

      setMessageText(msg);

      return;

    }



    const { frameCount, result } = await res.json();

    const searchTime = (performance.now() - startSearchTime) / 1000;



    setMessageText(

      frameCount > 0

        ? `Searched ${frameCount.toLocaleString(navigator.language)} frames in ${searchTime.toFixed(2)}s`

        : `Searched in ${searchTime.toFixed(2)}s`

    );



    if (!result || !result.length) {

      setMessageText("Cannot find any result");

      return;

    }



    const topSearchResults = result.slice(0, 5).map((entry) => {

      const meta = entry.anilistInfo || (typeof entry.anilist === "object" ? entry.anilist : null) || null;

      const isAdult = meta && typeof meta.isAdult === "boolean" ? meta.isAdult : false;

      return {

        ...entry,

        meta,

        isAdult,

        playResult: () => {

          setSelectedResult(entry);

          setPlayerSrc(entry.video);

          setPlayerFileName(entry.filename);

          setPlayerTimeCode(entry.from);

          setAnilistInfo(meta);

        }

      };

    });



    setSearchResults(topSearchResults);



    const firstResult = topSearchResults[0];

    if (firstResult && !firstResult.isAdult && window.innerWidth > 1008) firstResult.playResult();

  };



  return (

    <Layout title="Anime Scene Search Engine">

      <Head>

        <meta name="theme-color" content={SURFACE} />

        <meta itemProp="name" content="WAIT: What Anime Is This?" />

        <meta itemProp="description" content="Anime Scene Search Engine. Lookup the exact moment and the episode." />

        <meta itemProp="image" content="https://anime-seek.com/favicon128.png" />

        <meta name="twitter:card" content="summary_large_image" />

        <meta name="twitter:title" content="WAIT: What Anime Is This?" />

        <meta name="twitter:description" content="Anime Scene Search Engine. Lookup the exact moment and the episode." />

        <meta name="twitter:image" content="https://anime-seek.com/favicon128.png" />

        <meta name="twitter:image:alt" content="Anime Scene Search Engine. Lookup the exact moment and the episode." />

        <meta property="og:title" content="WAIT: What Anime Is This?" />

        <meta property="og:type" content="article" />

        <meta property="og:url" content="https://anime-seek.com" />

        <meta property="og:image" content="https://anime-seek.com/favicon128.png" />

        <meta property="og:description" content="Anime Scene Search Engine. Lookup the exact moment and the episode." />

        <meta property="og:site_name" content="anime-seek.com" />

        <link rel="dns-prefetch" href={NEXT_PUBLIC_API_ENDPOINT} />

      </Head>



      {/* inject target for WebExtension */}

      <img id="originalImage" src="" style={{ display: "none" }} onLoad={(e) => setSearchImageSrc(e.target.src)} alt="" />

      <input id="autoSearch" type="checkbox" style={{ display: "none" }} />



      <div

        id="appRoot"

        className={searchImageSrc ? mainReady : main}

        style={{ backgroundColor: SURFACE, color: TEXT, minHeight: "100vh" }}

      >

        {/* Single, original drop area only (no extra clickable uploader) */}

        {!searchImageSrc && (

          <div

            className={dropTarget}

            onDrop={handleFileSelect}

            onDragOver={(e) => {

              e.stopPropagation();

              e.preventDefault();

              e.dataTransfer.dropEffect = "copy";

            }}

            onDragEnter={(e) => {

              e.target.classList.add(dropping);

              setDropTargetText("Drop image here");

            }}

            onDragLeave={(e) => e.target.classList.remove(dropping)}

            style={{

              background: SURFACE,

              border: "1px solid #3A3F47",

              color: TEXT,

              borderRadius: 16,

            }}

          >

            {dropTargetText}

          </div>

        )}



        <SearchBar

          searchImageSrc={searchImageSrc}

          imageURL={imageURL}

          imageURLInput={imageURLInput}

          handleFileSelect={handleFileSelect}

          anilistFilter={anilistFilter}

          setAnilistFilter={setAnilistFilter}

          isCutBorders={isCutBorders}

          setIsCutBorders={setIsCutBorders}

          isSearching={isSearching}

          search={search}

          searchImage={searchImage}

        />



        {searchImageSrc && (

          <div className={wrap} style={{ background: SURFACE, backgroundImage: "none" }}>

            {/* Results keep their own colors */}

            <div className={resultList} style={{ background: SURFACE, backgroundImage: "none" }}>

              <div className={searchImageDisplay} style={{ background: SURFACE, backgroundImage: "none", color: TEXT }}>

                <div className={detail} style={{ color: TEXT, fontWeight: 600 }}>Your search image</div>

                <img

                  className={originalImageDisplay}

                  src={searchImageSrc}

                  crossOrigin="anonymous"

                  onError={() => setMessageText("Failed to load search image")}

                  style={{ borderRadius: 12, boxShadow: "0 10px 28px rgba(0,0,0,.50)" }}

                  alt="Search preview"

                />

                <div className={messageTextLabel} style={{ color: TEXT }}>{messageText}</div>

              </div>



              {searchResults

                .filter((e) => showNSFW || !e.isAdult)

                .map((searchResult, i) => (

                  <Result key={i} searchResult={searchResult} active={searchResult === selectedResult} />

                ))}



              {searchResults.find((e) => e.isAdult) && (

                <div style={{ textAlign: "center" }}>

                  <button

                    onClick={() => setshowNSFW(!showNSFW)}

                    style={{

                      background: SURFACE,

                      color: TEXT,

                      border: "1px solid #3A3F47",

                      borderRadius: 10,

                      padding: "10px 14px"

                    }}

                  >

                    {showNSFW ? "Hide" : "Show"} {searchResults.filter((e) => e.isAdult).length} NSFW results

                  </button>

                </div>

              )}

            </div>



            <div

              className={selectedResult ? playerInfoPane : [playerInfoPane, hidden].join(" ")}

              style={{ background: SURFACE, backgroundImage: "none", borderLeft: "1px solid #3A3F47", color: TEXT }}

            >

              <Player

                src={playerSrc}

                timeCode={playerTimeCode}

                fileName={playerFileName}

                isLoading={isLoading}

                isSearching={isSearching}

                onDrop={handleFileSelect}

              />

              <div

                className={closeBtn}

                onClick={() => {

                  setSelectedResult(undefined);

                  setAnilistInfo(undefined);

                  setPlayerSrc(undefined);

                  setPlayerFileName("");

                  setPlayerTimeCode("");

                }}

                style={{ filter: "grayscale(1)", opacity: 0.9 }}

                aria-label="Close details"

              >

                ❌

              </div>



              {/* Info panel forced white only */}

              {!isSearching && (

                <div data-info-panel style={{ color: "#FFFFFF" }}>

                  <Info anilist={anilistInfo} />

                </div>

              )}

            </div>

          </div>

        )}

      </div>



      {/* Global: base text white; keep results' own colors; Info panel forced white */}
      
            {/* Footer links */}
      <div style={{ maxWidth: 1100, margin: "26px auto 60px", padding: "0 16px" }}>
        <div style={{ borderTop: "1px solid #3A3F47", paddingTop: 14, opacity: 0.9 }}>
          <Link href="/about" legacyBehavior><a style={{ marginRight: 14, textDecoration: "underline", color: TEXT }}>About</a></Link>
          <Link href="/credits" legacyBehavior><a style={{ marginRight: 14, textDecoration: "underline", color: TEXT }}>Credits</a></Link>
          <Link href="/privacy" legacyBehavior><a style={{ marginRight: 14, textDecoration: "underline", color: TEXT }}>Privacy</a></Link>
          <Link href="/terms" legacyBehavior><a style={{ marginRight: 14, textDecoration: "underline", color: TEXT }}>Terms</a></Link>
          <Link href="/support" legacyBehavior><a style={{ marginRight: 14, textDecoration: "underline", color: TEXT }}>Support</a></Link>
        </div>
      </div>

      <style jsx global>{`

        :root { color-scheme: dark; }

        html, body, #__next { background: #22242A; }

        body { color: #FFFFFF; -webkit-font-smoothing: antialiased; -moz-osx-font-smoothing: grayscale; }



        button, input, select, textarea {

          background: #22242A;

          color: #FFFFFF;

          border: 1px solid #3A3F47;

          border-radius: 10px;

        }



        /* Kill any grid/patterns */

        #appRoot * { background-image: none !important; }



        /* Ensure Info panel text is white regardless of its internal styles */

        #appRoot [data-info-panel], 

        #appRoot [data-info-panel] * { color: #FFFFFF !important; }



        hr { border-color: #3A3F47; }

        * { scrollbar-width: thin; scrollbar-color: #3A3F47 #22242A; }

        *::-webkit-scrollbar { width: 10px; height: 10px; }

        *::-webkit-scrollbar-track { background: #22242A; }

        *::-webkit-scrollbar-thumb { background: #3A3F47; border-radius: 8px; }

      `}</style>

    </Layout>

  );

};



export default Index;