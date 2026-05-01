import { infoPane, title, subtitle, divider, poster, detail, footNotes } from "./info.module.css";

export default function Info({ anilist: src }) {
  if (!src || typeof src !== "object") return <div></div>;

  let naturalText1 = "";
  if (src.duration && src.episodes === 1) naturalText1 += `${src.duration} minutes `;
  if (src.episodes && src.format !== "MOVIE") naturalText1 += `${src.episodes} episode `;
  if (src.duration && src.episodes > 1) naturalText1 += `${src.duration}-minute `;
  if (src.format) naturalText1 += `${src.format.length > 3 ? src.format.toLowerCase() : src.format} `;
  naturalText1 += " anime. ";

  const strStartDate =
    src.startDate?.year && src.startDate?.month && src.startDate?.day
      ? `${src.startDate.year}-${src.startDate.month}-${src.startDate.day}`
      : null;
  const strEndDate =
    src.endDate?.year && src.endDate?.month && src.endDate?.day
      ? `${src.endDate.year}-${src.endDate.month}-${src.endDate.day}`
      : null;

  let naturalText2 = "";
  if (strStartDate && strEndDate) {
    if (src.format === "MOVIE") {
      naturalText2 += strStartDate === strEndDate
        ? `Released on ${strStartDate}`
        : `Released during ${strStartDate} to ${strEndDate}`;
    } else {
      naturalText2 += strStartDate === strEndDate
        ? `Released on ${strStartDate}`
        : `Airing from ${strStartDate} to ${strEndDate}`;
    }
  } else if (strStartDate && (src.format === "TV" || src.format === "TV_SHORT")) {
    naturalText2 += `Airing since ${strStartDate}`;
  }
  if (naturalText2) naturalText2 += ". ";

  const synonyms = Array.from(
    new Set(
      [
        src?.title?.chinese || "",
        src?.title?.english || "",
        ...(src.synonyms || []),
        ...(src.synonyms_chinese || []),
      ]
        .filter(Boolean)
        .filter((e) => e !== src?.title?.native && e !== src?.title?.romaji),
    ),
  )
    .sort()
    .map((t, i) => <div key={i}>{t}</div>);

  const studio =
    src?.studios?.edges?.length
      ? src.studios.edges.map((entry, i) =>
          entry.node?.siteUrl ? (
            <div key={i}>
              <a href={entry.node.siteUrl}>{entry.node.name}</a>
            </div>
          ) : (
            <div key={i}>{entry.node?.name}</div>
          ),
        )
      : [];

  const externalLinks =
    src?.externalLinks?.length
      ? src.externalLinks.map((entry, i) => (
          <div key={i}>
            <a href={entry.url}>{entry.site}</a>
          </div>
        ))
      : [];

  return (
    <div className={infoPane}>
      <div className={title}>
        {src?.title?.native || src?.title?.romaji || src?.title?.english || "Unknown"}
      </div>
      <div className={subtitle}>{src?.title?.romaji || src?.title?.english || ""}</div>
      <div className={divider}></div>

      <div className={detail}>
        <table>
          <tbody>
            <tr>
              <td colSpan={2}>
                {naturalText1}
                <br />
                {naturalText2}
              </td>
            </tr>
            <tr>
              <td>Alias</td>
              <td>{synonyms}</td>
            </tr>
            <tr>
              <td>Genre</td>
              <td>{(src?.genres || []).join(", ")}</td>
            </tr>
            <tr>
              <td>Studio</td>
              <td>{studio}</td>
            </tr>
            <tr>
              <td>External Links</td>
              <td>{externalLinks}</td>
            </tr>
          </tbody>
        </table>
        <div className={poster}>
          <a href={`//anilist.co/anime/${src.id}`}>
            <img
              key={src?.coverImage?.large}
              src={src?.coverImage?.large}
              style={{ opacity: 0 }}
              onLoad={(e) => (e.target.style.opacity = 1)}
              alt={src?.title?.romaji || src?.title?.english || "cover"}
            />
          </a>
        </div>
      </div>
      <div className={divider}></div>
      <div className={footNotes}>
        Information provided by <a href="https://anilist.co">anilist.co</a>
      </div>
    </div>
  );
}
