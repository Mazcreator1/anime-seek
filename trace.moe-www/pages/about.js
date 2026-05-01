import { useEffect, useState } from "react";
import {
  Chart as ChartJS,
  CategoryScale,
  LinearScale,
  BarElement,
  Title,
  Tooltip,
  PointElement,
  LineElement,
  Legend,
} from "chart.js";
import { Bar, Line } from "react-chartjs-2";
import Layout from "../components/layout";
import {
  container,
  page,
  pageHeader,
  section,
  sectionHeader,
  sectionItem,
  graph,
  graphControl,
  numberInput,
  fileList,
} from "../components/layout.module.css";

const NEXT_PUBLIC_API_ENDPOINT = process.env.NEXT_PUBLIC_API_ENDPOINT;

ChartJS.register(
  CategoryScale,
  LinearScale,
  BarElement,
  PointElement,
  LineElement,
  Title,
  Tooltip,
  Legend,
);

const getDatabaseStatus = async () => {
  const status = await fetch(`${NEXT_PUBLIC_API_ENDPOINT}/status`).then((e) => e.json());
  let numDocs = 0;
  let totalSize = 0;
  let lastModified = new Date(0);
  for (const [_, server] of Object.entries(status)) {
    for (const core of server) {
      numDocs += core.index.numDocs;
      totalSize += core.index.sizeInBytes;
      lastModified =
        lastModified > new Date(core.index.lastModified)
          ? lastModified
          : new Date(core.index.lastModified);
    }
  }
  return {
    lastModified,
    numDocs,
    totalSize,
  };
};

const getMediaStatus = async () => {
  const { mediaCount, mediaFramesTotal, mediaDurationTotal } = await fetch(
    `${NEXT_PUBLIC_API_ENDPOINT}/stats?type=media`,
  ).then((e) => e.json());
  return {
    mediaCount,
    mediaFramesTotal,
    mediaDurationTotal,
  };
};

const formatDate = (time, trafficPeriod) => {
  const isoString = new Date(time).toISOString();
  if (trafficPeriod === "year") return isoString.replace(/(\d+)-(\d+)-(\d+)T(\d+):.*$/, "$1");
  if (trafficPeriod === "month") return isoString.replace(/(\d+)-(\d+)-(\d+)T(\d+):.*$/, "$1-$2");
  if (trafficPeriod === "day") return isoString.replace(/(\d+)-(\d+)-(\d+)T(\d+):.*$/, "$2-$3");
  if (trafficPeriod === "hour") return isoString.replace(/(\d+)-(\d+)-(\d+)T(\d+):.*$/, "$4:00");
};

const About = () => {
  const [message, setMessage] = useState("");
  const [{ lastModified, numDocs, totalSize }, setDatabaseStatus] = useState({
    lastModified: null,
    numDocs: 0,
    totalSize: 0,
  });
  const [{ mediaCount, mediaFramesTotal, mediaDurationTotal }, setMediaStatus] = useState({
    mediaCount: 0,
    mediaFramesTotal: 0,
    mediaDurationTotal: 0,
  });

  useEffect(() => {
    getDatabaseStatus().then((e) => setDatabaseStatus(e));
    getMediaStatus().then((e) => setMediaStatus(e));
  }, []);

  const [trafficPeriod, setTrafficPeriod] = useState("hour");
  const [trafficData, setTrafficData] = useState(null);
  useEffect(() => {
    fetch(`${NEXT_PUBLIC_API_ENDPOINT}/stats?type=traffic&period=${trafficPeriod}`)
      .then((e) => e.json())
      .then((stats) => {
        stats.sort((a, b) => new Date(a.time) - new Date(b.time));
        setTrafficData({
          labels: stats.map((e) => formatDate(e.time, trafficPeriod)),
          datasets: [
            { label: "200", data: stats.map((e) => e["200"]), backgroundColor: ["rgba(0,255,0,0.2)"], borderColor: ["rgba(0,255,0,1)"], borderWidth: 1 },
            { label: "400", data: stats.map((e) => e["400"]), backgroundColor: ["rgba(192,192,0,0.2)"], borderColor: ["rgba(192,192,0,1)"], borderWidth: 1 },
            { label: "402", data: stats.map((e) => e["402"]), backgroundColor: ["rgba(128,128,255,0.2)"], borderColor: ["rgba(128,128,255,1)"], borderWidth: 1 },
            { label: "405", data: stats.map((e) => e["405"]), backgroundColor: ["rgba(128,128,128,0.2)"], borderColor: ["rgba(128,128,128,1)"], borderWidth: 1 },
            { label: "500", data: stats.map((e) => e["500"]), backgroundColor: ["rgba(255,128,255,0.2)"], borderColor: ["rgba(255,128,255,1)"], borderWidth: 1 },
            { label: "503", data: stats.map((e) => e["503"]), backgroundColor: ["rgba(255,128,128,0.2)"], borderColor: ["rgba(255,128,128,1)"], borderWidth: 1 },
          ],
        });
      });
  }, [trafficPeriod]);

  const [speedPeriod, setSpeedPeriod] = useState("hour");
  const [speedData, setSpeedData] = useState(null);
  useEffect(() => {
    fetch(`${NEXT_PUBLIC_API_ENDPOINT}/stats?type=speed&period=${speedPeriod}`)
      .then((e) => e.json())
      .then((stats) => {
        stats.sort((a, b) => new Date(a.time) - new Date(b.time));
        setSpeedData({
          labels: stats.map((e) => formatDate(e.time, speedPeriod)),
          datasets: [
            { label: "p0", data: stats.map((e) => (e.p0 ? e.p0 : null)), borderColor: "rgba(64,64,64,0)", backgroundColor: "rgba(64,64,64,0)", borderWidth: 1, cubicInterpolationMode: "monotone", pointHitRadius: 8, pointRadius: 1, pointHoverRadius: 3, pointBackgroundColor: "rgba(64,64,64,0.5)", hidden: true },
            { label: "p10", data: stats.map((e) => (e.p10 ? e.p10 : null)), borderColor: "rgba(64,64,64,0.2)", backgroundColor: "rgba(64,64,64,0.2)", borderWidth: 1, cubicInterpolationMode: "monotone", pointHitRadius: 8, pointRadius: 0, pointHoverRadius: 3, pointBackgroundColor: "rgba(64,64,64,0.5)" },
            { label: "p25", data: stats.map((e) => (e.p25 ? e.p25 : null)), borderColor: "hsl(227, 100%, 70%)", backgroundColor: "hsl(227, 100%, 70%)", borderWidth: 1, cubicInterpolationMode: "monotone", pointHitRadius: 8, pointRadius: 0, pointHoverRadius: 3, pointBackgroundColor: "hsl(227, 100%, 70%)" },
            { label: "p50", data: stats.map((e) => (e.p50 ? e.p50 : null)), borderColor: "hsl(0, 100%, 66%)", backgroundColor: "hsl(0, 100%, 66%)", borderWidth: 1, cubicInterpolationMode: "monotone", pointHitRadius: 8, pointRadius: 0, pointHoverRadius: 3, pointBackgroundColor: "hsl(0, 100%, 66%)" },
            { label: "p75", data: stats.map((e) => (e.p75 ? e.p75 : null)), borderColor: "hsl(227, 100%, 70%)", backgroundColor: "hsl(227, 100%, 70%)", borderWidth: 1, cubicInterpolationMode: "monotone", pointHitRadius: 8, pointRadius: 0, pointHoverRadius: 3, pointBackgroundColor: "hsl(227, 100%, 70%)" },
            { label: "p90", data: stats.map((e) => (e.p90 ? e.p90 : null)), borderColor: "rgba(64,64,64,0.2)", backgroundColor: "rgba(64,64,64,0.2)", borderWidth: 1, cubicInterpolationMode: "monotone", pointHitRadius: 8, pointRadius: 0, pointHoverRadius: 3, pointBackgroundColor: "rgba(64,64,64,0.5)" },
            { label: "p100", data: stats.map((e) => (e.p100 ? e.p100 : null)), borderColor: "rgba(64,64,64,0)", backgroundColor: "rgba(64,64,64,0)", borderWidth: 1, cubicInterpolationMode: "monotone", pointHitRadius: 8, pointRadius: 1, pointHoverRadius: 3, pointBackgroundColor: "rgba(64,64,64,0.5)", hidden: true },
          ],
        });
      });
  }, [speedPeriod]);

  const [accuracyPeriod, setAccuracyPeriod] = useState("hour");
  const [accuracyData, setAccuracyData] = useState(null);
  useEffect(() => {
    fetch(`${NEXT_PUBLIC_API_ENDPOINT}/stats?type=accuracy&period=${accuracyPeriod}`)
      .then((e) => e.json())
      .then((stats) => {
        stats.sort((a, b) => new Date(a.time) - new Date(b.time));
        setAccuracyData({
          labels: stats.map((e) => formatDate(e.time, accuracyPeriod)),
          datasets: [
            { label: "p0", data: stats.map((e) => (e.p0 ? Number(e.p0?.toFixed(3)) : null)), borderColor: "rgba(64,64,64,0)", backgroundColor: "rgba(64,64,64,0)", borderWidth: 1, cubicInterpolationMode: "monotone", pointHitRadius: 8, pointRadius: 1, pointHoverRadius: 3, pointBackgroundColor: "rgba(64,64,64,0.5)", hidden: true },
            { label: "p10", data: stats.map((e) => (e.p10 ? Number(e.p10?.toFixed(3)) : null)), borderColor: "rgba(64,64,64,0.2)", backgroundColor: "rgba(64,64,64,0.2)", borderWidth: 1, cubicInterpolationMode: "monotone", pointHitRadius: 8, pointRadius: 0, pointHoverRadius: 3, pointBackgroundColor: "rgba(64,64,64,0.5)" },
            { label: "p25", data: stats.map((e) => (e.p25 ? Number(e.p25?.toFixed(3)) : null)), borderColor: "hsl(227, 100%, 70%)", backgroundColor: "hsl(227, 100%, 70%)", borderWidth: 1, cubicInterpolationMode: "monotone", pointHitRadius: 8, pointRadius: 0, pointHoverRadius: 3, pointBackgroundColor: "hsl(227, 100%, 70%)" },
            { label: "p50", data: stats.map((e) => (e.p50 ? Number(e.p50?.toFixed(3)) : null)), borderColor: "hsl(0, 100%, 66%)", backgroundColor: "hsl(0, 100%, 66%)", borderWidth: 1, cubicInterpolationMode: "monotone", pointHitRadius: 8, pointRadius: 0, pointHoverRadius: 3, pointBackgroundColor: "hsl(0, 100%, 66%)" },
            { label: "p75", data: stats.map((e) => (e.p75 ? Number(e.p75?.toFixed(3)) : null)), borderColor: "hsl(227, 100%, 70%)", backgroundColor: "hsl(227, 100%, 70%)", borderWidth: 1, cubicInterpolationMode: "monotone", pointHitRadius: 8, pointRadius: 0, pointHoverRadius: 3, pointBackgroundColor: "hsl(227, 100%, 70%)" },
            { label: "p90", data: stats.map((e) => (e.p90 ? Number(e.p90?.toFixed(3)) : null)), borderColor: "rgba(64,64,64,0.2)", backgroundColor: "rgba(64,64,64,0.2)", borderWidth: 1, cubicInterpolationMode: "monotone", pointHitRadius: 8, pointRadius: 0, pointHoverRadius: 3, pointBackgroundColor: "rgba(64,64,64,0.5)" },
            { label: "p100", data: stats.map((e) => (e.p100 ? Number(e.p100?.toFixed(3)) : null)), borderColor: "rgba(64,64,64,0)", backgroundColor: "rgba(64,64,64,0)", borderWidth: 1, cubicInterpolationMode: "monotone", pointHitRadius: 8, pointRadius: 1, pointHoverRadius: 3, pointBackgroundColor: "rgba(64,64,64,0.5)", hidden: true },
          ],
        });
      });
  }, [accuracyPeriod]);

  return (
    <Layout title="About">
      <div className={`${container} ${page}`}>
        <div className={pageHeader}>About</div>

        <div className={section}>
          <div className={sectionHeader}>What is Anime Seek?</div>
          <p>
            <b>Anime Seek is an Anime Scene Search Engine</b> that helps you identify the original anime
            from a screenshot. Upload an image, and Anime Seek will return the best matching scene with
            the anime title, episode, and timestamp.
          </p>
          <p>
            Anime Seek is designed to make it easy to credit and discover the original source of anime
            screenshots.
          </p>
          <p style={{ opacity: 0.9 }}>
            <b>Note:</b> Anime Seek runs a self-hosted search backend. It stores only vector data used
            for matching and does not provide episode previews or full video playback.
          </p>
        </div>

        <div className={section}>
          <div className={sectionHeader}>What Anime Seek is NOT</div>

          <p>
            <b>This website is not for watching anime</b>. Anime Seek does not host or stream full
            anime episodes.
          </p>

          <p>
            <b>Anime Seek is not for comics or anime-style artwork</b>. This engine is intended for
            identifying frames from officially released anime episodes. If you want to search fan art or
            wallpapers, try <a href="https://saucenao.com/">SauceNAO</a> or{" "}
            <a href="https://iqdb.org/">iqdb.org</a>.
          </p>

          <p>
            <b>Anime Seek is not an AI character recognizer</b>. It does not understand scenes like a
            machine-learning model. It uses{" "}
            <a href="https://en.wikipedia.org/wiki/Content-based_image_retrieval">
              content-based image retrieval
            </a>{" "}
            and vector similarity matching to compare visual patterns.
          </p>
        </div>

        <div className={section}>
          <div className={sectionHeader}>System Status</div>
          <p>
            This page displays internal indexing and service metrics for the Anime Seek search backend.
          </p>

          <ul>
            <li>Analyzed Media: {mediaCount ? mediaCount.toLocaleString(navigator.language) : "counting..."}</li>
            <li>
              Total Duration:{" "}
              {mediaDurationTotal
                ? `${Number((mediaDurationTotal / 3600).toFixed(2)).toLocaleString(
                    navigator.language,
                  )} hours`
                : "counting..."}
            </li>
            <li>
              Analyzed Frames:{" "}
              {mediaFramesTotal ? mediaFramesTotal.toLocaleString(navigator.language) : "counting..."}
            </li>
            <li>
              Indexed Frames: {numDocs ? numDocs.toLocaleString(navigator.language) : "counting..."}{" "}
              {numDocs && mediaFramesTotal
                ? `(${((1 - numDocs / mediaFramesTotal) * 100).toFixed(2)}% de-duplicated)`
                : ""}
            </li>
            <li>Index Size: {totalSize ? `${(totalSize / 1000000000).toFixed(2)} GB` : "calculating..."}</li>
          </ul>

          <p>Last Database Update: {lastModified ? lastModified.toString() : ""}</p>

          <p>
            Check database coverage by AniList ID:{" "}
            <input
              className={numberInput}
              type="number"
              min="0"
              max="1000000"
              onChange={async (e) => {
                if (!e.target.value.match(/\d+/)) return;
                setMessage("Searching...");
                const status = await fetch(
                  `${NEXT_PUBLIC_API_ENDPOINT}/status?id=${e.target.value}`,
                ).then((e) => e.json());
                setMessage(`Found ${status.length} records`);
                const pre = document.querySelector("pre");
                if (!pre) return;

                if (status.length) {
                  pre.innerText = status.map((e) => e.path.split("/").slice(1)).join("\n");
                } else {
                  pre.innerText = `Cannot find any record for ID ${e.target.value}`;
                }
              }}
            />
            {" "}{message}
          </p>

          <pre className={fileList}></pre>

          {trafficData ? (
            <Bar
              className={graph}
              options={{
                animations: false,
                plugins: { title: { display: true, text: "Anime Seek search traffic" } },
                scales: {
                  x: { stacked: true, distribution: "series", ticks: { maxRotation: 0 } },
                  y: { beginAtZero: true, stacked: true },
                },
              }}
              data={trafficData}
              width="680"
              height="500"
            />
          ) : (
            <div className={graph}></div>
          )}
          <p className={graphControl}>
            <button onClick={() => setTrafficPeriod("hour")}>hourly</button>
            <button onClick={() => setTrafficPeriod("day")}>daily</button>
            <button onClick={() => setTrafficPeriod("month")}>monthly</button>
            <button onClick={() => setTrafficPeriod("year")}>yearly</button>
          </p>

          {speedData ? (
            <Line
              className={graph}
              options={{
                animations: false,
                plugins: { title: { display: true, text: "Anime Seek search time distribution" } },
                scales: {
                  x: { stacked: true, distribution: "series", ticks: { maxRotation: 0 } },
                  y: { beginAtZero: true, title: { display: true, text: "time (ms)" } },
                },
              }}
              data={speedData}
              width="680"
              height="500"
            />
          ) : (
            <div className={graph}></div>
          )}
          <p className={graphControl}>
            <button onClick={() => setSpeedPeriod("hour")}>hourly</button>
            <button onClick={() => setSpeedPeriod("day")}>daily</button>
          </p>

          {accuracyData ? (
            <Line
              className={graph}
              options={{
                animations: false,
                plugins: { title: { display: true, text: "Anime Seek match confidence distribution" } },
                scales: {
                  x: { stacked: true, distribution: "series", ticks: { maxRotation: 0 } },
                  y: { title: { display: true, text: "confidence (1=100%)" } },
                },
              }}
              data={accuracyData}
              width="680"
              height="500"
            />
          ) : (
            <div className={graph}></div>
          )}
          <p className={graphControl}>
            <button onClick={() => setAccuracyPeriod("hour")}>hourly</button>
            <button onClick={() => setAccuracyPeriod("day")}>daily</button>
          </p>
        </div>

        <div className={section}>
          <div className={sectionHeader}>Credits & Attribution</div>

          <div className={sectionItem}>
            <b>AniList</b> — metadata and cover images (<a href="https://anilist.co/">anilist.co</a>)
          </div>

          <div className={sectionItem}>
            <b>trace.moe (Soruly)</b> — open-source inspiration for anime scene search workflows (self-hosted instance)
            (<a href="https://github.com/soruly/trace.moe">GitHub</a>)
          </div>

          <div className={sectionItem}>
            <b>CBIR / Image Retrieval References</b>
            <div style={{ marginTop: 8 }}>
              Dr. Mathias Lux (<a href="http://www.lire-project.net/">LIRE Project</a>)
              <br />
              <small>
                Lux Mathias, Savvas A. Chatzichristofis. Lire: Lucene Image Retrieval – An Extensible
                Java CBIR Library. In proceedings of the 16th ACM International Conference on
                Multimedia, pp. 1085-1088, Vancouver, Canada, 2008.{" "}
                <a href="http://www.morganclaypool.com/doi/abs/10.2200/S00468ED1V01Y201301ICR025">
                  Visual Information Retrieval with Java and LIRE
                </a>
              </small>
            </div>
          </div>

          <small style={{ opacity: 0.85 }}>
            Anime Seek is not affiliated with or endorsed by AniList or trace.moe. All trademarks and
            referenced content belong to their respective owners.
          </small>
        </div>
      </div>
    </Layout>
  );
};

export default About;