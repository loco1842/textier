// The bundled Grok Definitions: the 74 names StreamSets Data Collector documents
// (IBM StreamSets, "Grok patterns" appendix), as one flat list in its order, then
// the three Logstash definitions COMMONAPACHELOG's body refers to, with
// bodies from Logstash's logstash-patterns-core `legacy` set
// (https://github.com/logstash-plugins/logstash-patterns-core, commit 74a4098,
// `patterns/legacy/grok-patterns`, `java` and `httpd`).
//
// Apache License 2.0; its NOTICE ships with textier (`NOTICE-logstash-patterns-core.txt`).
//
// Changes from Logstash: `HOST` (not in `legacy`) is `%{HOSTNAME}`, as StreamSets
// defines it; `COMMONAPACHELOG` takes the body of `HTTPD_COMMONLOG`, which it
// aliases, and `COMBINEDAPACHELOG` is written out from `HTTPD_COMBINEDLOG`'s body;
// `UNIXPATH` spells Oniguruma's nested POSIX class `[[:alnum:]]` as `\p{Alnum}`
// and escapes `$`, so the class means in ICU what it means in Logstash;
// `URIPROTO` drops the group around its repeated class (`[A-Za-z]([…]+)+` is
// `[A-Za-z][…]+`), which matches the same text without backtracking for seconds
// over a word that isn't followed by `://`.
//
// Embedded as source, like the bundled themes, because the app bundle is
// assembled from the bare binary (`scripts/bundle.sh`).

extension GrokDefinition {
    /// The Grok Definitions that ship with textier, in StreamSets' order.
    public static let bundled: [GrokDefinition] = [
        GrokDefinition(name: "USER", regex: #"%{USERNAME}"#),
        GrokDefinition(name: "USERNAME", regex: #"[a-zA-Z0-9._-]+"#),
        GrokDefinition(name: "BASE10NUM", regex: #"(?<![0-9.+-])(?>[+-]?(?:(?:[0-9]+(?:\.[0-9]+)?)|(?:\.[0-9]+)))"#),
        GrokDefinition(name: "BASE16FLOAT", regex: #"\b(?<![0-9A-Fa-f.])(?:[+-]?(?:0x)?(?:(?:[0-9A-Fa-f]+(?:\.[0-9A-Fa-f]*)?)|(?:\.[0-9A-Fa-f]+)))\b"#),
        GrokDefinition(name: "INT", regex: #"(?:[+-]?(?:[0-9]+))"#),
        GrokDefinition(name: "NONNEGINT", regex: #"\b(?:[0-9]+)\b"#),
        GrokDefinition(name: "NUMBER", regex: #"(?:%{BASE10NUM})"#),
        GrokDefinition(name: "BASE16NUM", regex: #"(?<![0-9A-Fa-f])(?:[+-]?(?:0x)?(?:[0-9A-Fa-f]+))"#),
        GrokDefinition(name: "POSINT", regex: #"\b(?:[1-9][0-9]*)\b"#),
        GrokDefinition(name: "WORD", regex: #"\b\w+\b"#),
        GrokDefinition(name: "NOTSPACE", regex: #"\S+"#),
        GrokDefinition(name: "SPACE", regex: #"\s*"#),
        GrokDefinition(name: "DATA", regex: #".*?"#),
        GrokDefinition(name: "GREEDYDATA", regex: #".*"#),
        GrokDefinition(name: "QUOTEDSTRING", regex: #"(?>(?<!\\)(?>"(?>\\.|[^\\"]+)+"|""|(?>'(?>\\.|[^\\']+)+')|''|(?>`(?>\\.|[^\\`]+)+`)|``))"#),
        GrokDefinition(name: "UUID", regex: #"[A-Fa-f0-9]{8}-(?:[A-Fa-f0-9]{4}-){3}[A-Fa-f0-9]{12}"#),
        GrokDefinition(name: "MONTH", regex: #"\b(?:[Jj]an(?:uary|uar)?|[Ff]eb(?:ruary|ruar)?|[Mm](?:a|ä)?r(?:ch|z)?|[Aa]pr(?:il)?|[Mm]a(?:y|i)?|[Jj]un(?:e|i)?|[Jj]ul(?:y|i)?|[Aa]ug(?:ust)?|[Ss]ep(?:tember)?|[Oo](?:c|k)?t(?:ober)?|[Nn]ov(?:ember)?|[Dd]e(?:c|z)(?:ember)?)\b"#),
        GrokDefinition(name: "MONTHNUM", regex: #"(?:0?[1-9]|1[0-2])"#),
        GrokDefinition(name: "MONTHNUM2", regex: #"(?:0[1-9]|1[0-2])"#),
        GrokDefinition(name: "MONTHDAY", regex: #"(?:(?:0[1-9])|(?:[12][0-9])|(?:3[01])|[1-9])"#),
        GrokDefinition(name: "DAY", regex: #"(?:Mon(?:day)?|Tue(?:sday)?|Wed(?:nesday)?|Thu(?:rsday)?|Fri(?:day)?|Sat(?:urday)?|Sun(?:day)?)"#),
        GrokDefinition(name: "YEAR", regex: #"(?>\d\d){1,2}"#),
        GrokDefinition(name: "HOUR", regex: #"(?:2[0123]|[01]?[0-9])"#),
        GrokDefinition(name: "MINUTE", regex: #"(?:[0-5][0-9])"#),
        GrokDefinition(name: "SECOND", regex: #"(?:(?:[0-5]?[0-9]|60)(?:[:.,][0-9]+)?)"#),
        GrokDefinition(name: "TIME", regex: #"(?!<[0-9])%{HOUR}:%{MINUTE}(?::%{SECOND})(?![0-9])"#),
        GrokDefinition(name: "DATE_US", regex: #"%{MONTHNUM}[/-]%{MONTHDAY}[/-]%{YEAR}"#),
        GrokDefinition(name: "DATE_EU", regex: #"%{MONTHDAY}[./-]%{MONTHNUM}[./-]%{YEAR}"#),
        GrokDefinition(name: "ISO8601_TIMEZONE", regex: #"(?:Z|[+-]%{HOUR}(?::?%{MINUTE}))"#),
        GrokDefinition(name: "ISO8601_SECOND", regex: #"(?:%{SECOND}|60)"#),
        GrokDefinition(name: "TIMESTAMP_ISO8601", regex: #"%{YEAR}-%{MONTHNUM}-%{MONTHDAY}[T ]%{HOUR}:?%{MINUTE}(?::?%{SECOND})?%{ISO8601_TIMEZONE}?"#),
        GrokDefinition(name: "DATE", regex: #"%{DATE_US}|%{DATE_EU}"#),
        GrokDefinition(name: "DATESTAMP", regex: #"%{DATE}[- ]%{TIME}"#),
        GrokDefinition(name: "TZ", regex: #"(?:[APMCE][SD]T|UTC)"#),
        GrokDefinition(name: "DATESTAMP_RFC822", regex: #"%{DAY} %{MONTH} %{MONTHDAY} %{YEAR} %{TIME} %{TZ}"#),
        GrokDefinition(name: "DATESTAMP_RFC2822", regex: #"%{DAY}, %{MONTHDAY} %{MONTH} %{YEAR} %{TIME} %{ISO8601_TIMEZONE}"#),
        GrokDefinition(name: "DATESTAMP_OTHER", regex: #"%{DAY} %{MONTH} %{MONTHDAY} %{TIME} %{TZ} %{YEAR}"#),
        GrokDefinition(name: "DATESTAMP_EVENTLOG", regex: #"%{YEAR}%{MONTHNUM2}%{MONTHDAY}%{HOUR}%{MINUTE}%{SECOND}"#),
        GrokDefinition(name: "JAVACLASS", regex: #"(?:[a-zA-Z$_][a-zA-Z$_0-9]*\.)*[a-zA-Z$_][a-zA-Z$_0-9]*"#),
        GrokDefinition(name: "JAVAFILE", regex: #"(?:[a-zA-Z$_0-9. -]+)"#),
        GrokDefinition(name: "JAVAMETHOD", regex: #"(?:(<(?:cl)?init>)|[a-zA-Z$_][a-zA-Z$_0-9]*)"#),
        GrokDefinition(name: "JAVASTACKTRACEPART", regex: #"%{SPACE}at %{JAVACLASS:class}\.%{JAVAMETHOD:method}\(%{JAVAFILE:file}(?::%{NUMBER:line})?\)"#),
        GrokDefinition(name: "SYSLOGTIMESTAMP", regex: #"%{MONTH} +%{MONTHDAY} %{TIME}"#),
        GrokDefinition(name: "PROG", regex: #"[\x21-\x5a\x5c\x5e-\x7e]+"#),
        GrokDefinition(name: "SYSLOGPROG", regex: #"%{PROG:program}(?:\[%{POSINT:pid}\])?"#),
        GrokDefinition(name: "SYSLOGHOST", regex: #"%{IPORHOST}"#),
        GrokDefinition(name: "SYSLOGFACILITY", regex: #"<%{NONNEGINT:facility}.%{NONNEGINT:priority}>"#),
        GrokDefinition(name: "SYSLOGBASE", regex: #"%{SYSLOGTIMESTAMP:timestamp} (?:%{SYSLOGFACILITY} )?%{SYSLOGHOST:logsource} %{SYSLOGPROG}:"#),
        GrokDefinition(name: "HTTPDATE", regex: #"%{MONTHDAY}/%{MONTH}/%{YEAR}:%{TIME} %{INT}"#),
        GrokDefinition(name: "QS", regex: #"%{QUOTEDSTRING}"#),
        GrokDefinition(name: "COMMONAPACHELOG", regex: #"%{IPORHOST:clientip} %{HTTPDUSER:ident} %{HTTPDUSER:auth} \[%{HTTPDATE:timestamp}\] "(?:%{WORD:verb} %{NOTSPACE:request}(?: HTTP/%{NUMBER:httpversion})?|%{DATA:rawrequest})" (?:-|%{NUMBER:response}) (?:-|%{NUMBER:bytes})"#),
        GrokDefinition(name: "COMBINEDAPACHELOG", regex: #"%{COMMONAPACHELOG} %{QS:referrer} %{QS:agent}"#),
        GrokDefinition(name: "LOGLEVEL", regex: #"([Aa]lert|ALERT|[Tt]race|TRACE|[Dd]ebug|DEBUG|[Nn]otice|NOTICE|[Ii]nfo?(?:rmation)?|INFO?(?:RMATION)?|[Ww]arn?(?:ing)?|WARN?(?:ING)?|[Ee]rr?(?:or)?|ERR?(?:OR)?|[Cc]rit?(?:ical)?|CRIT?(?:ICAL)?|[Ff]atal|FATAL|[Ss]evere|SEVERE|EMERG(?:ENCY)?|[Ee]merg(?:ency)?)"#),
        GrokDefinition(name: "MAC", regex: #"(?:%{CISCOMAC}|%{WINDOWSMAC}|%{COMMONMAC})"#),
        GrokDefinition(name: "CISCOMAC", regex: #"(?:(?:[A-Fa-f0-9]{4}\.){2}[A-Fa-f0-9]{4})"#),
        GrokDefinition(name: "COMMONMAC", regex: #"(?:(?:[A-Fa-f0-9]{2}:){5}[A-Fa-f0-9]{2})"#),
        GrokDefinition(name: "WINDOWSMAC", regex: #"(?:(?:[A-Fa-f0-9]{2}-){5}[A-Fa-f0-9]{2})"#),
        GrokDefinition(name: "HOST", regex: #"%{HOSTNAME}"#),
        GrokDefinition(name: "HOSTNAME", regex: #"\b(?:[0-9A-Za-z][0-9A-Za-z-]{0,62})(?:\.(?:[0-9A-Za-z][0-9A-Za-z-]{0,62}))*(\.?|\b)"#),
        GrokDefinition(name: "HOSTPORT", regex: #"%{IPORHOST}:%{POSINT}"#),
        GrokDefinition(name: "IPORHOST", regex: #"(?:%{IP}|%{HOSTNAME})"#),
        GrokDefinition(name: "IP", regex: #"(?:%{IPV6}|%{IPV4})"#),
        GrokDefinition(name: "IPV6", regex: #"((([0-9A-Fa-f]{1,4}:){7}([0-9A-Fa-f]{1,4}|:))|(([0-9A-Fa-f]{1,4}:){6}(:[0-9A-Fa-f]{1,4}|((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3})|:))|(([0-9A-Fa-f]{1,4}:){5}(((:[0-9A-Fa-f]{1,4}){1,2})|:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3})|:))|(([0-9A-Fa-f]{1,4}:){4}(((:[0-9A-Fa-f]{1,4}){1,3})|((:[0-9A-Fa-f]{1,4})?:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:))|(([0-9A-Fa-f]{1,4}:){3}(((:[0-9A-Fa-f]{1,4}){1,4})|((:[0-9A-Fa-f]{1,4}){0,2}:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:))|(([0-9A-Fa-f]{1,4}:){2}(((:[0-9A-Fa-f]{1,4}){1,5})|((:[0-9A-Fa-f]{1,4}){0,3}:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:))|(([0-9A-Fa-f]{1,4}:){1}(((:[0-9A-Fa-f]{1,4}){1,6})|((:[0-9A-Fa-f]{1,4}){0,4}:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:))|(:(((:[0-9A-Fa-f]{1,4}){1,7})|((:[0-9A-Fa-f]{1,4}){0,5}:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:)))(%.+)?"#),
        GrokDefinition(name: "IPV4", regex: #"(?<![0-9])(?:(?:[0-1]?[0-9]{1,2}|2[0-4][0-9]|25[0-5])[.](?:[0-1]?[0-9]{1,2}|2[0-4][0-9]|25[0-5])[.](?:[0-1]?[0-9]{1,2}|2[0-4][0-9]|25[0-5])[.](?:[0-1]?[0-9]{1,2}|2[0-4][0-9]|25[0-5]))(?![0-9])"#),
        GrokDefinition(name: "PATH", regex: #"(?:%{UNIXPATH}|%{WINPATH})"#),
        GrokDefinition(name: "UNIXPATH", regex: #"(/[\p{Alnum}_%!\$@:.,+~-]*)+"#),
        GrokDefinition(name: "TTY", regex: #"(?:/dev/(pts|tty([pq])?)(\w+)?/?(?:[0-9]+))"#),
        GrokDefinition(name: "WINPATH", regex: #"(?>[A-Za-z]+:|\\)(?:\\[^\\?*]*)+"#),
        GrokDefinition(name: "URIPROTO", regex: #"[A-Za-z][A-Za-z0-9+\-.]+"#),
        GrokDefinition(name: "URIHOST", regex: #"%{IPORHOST}(?::%{POSINT:port})?"#),
        GrokDefinition(name: "URIPATH", regex: #"(?:/[A-Za-z0-9$.+!*'(){},~:;=@#%&_\-]*)+"#),
        GrokDefinition(name: "URIPARAM", regex: #"\?[A-Za-z0-9$.+!*'|(){},~@#%&/=:;_?\-\[\]<>]*"#),
        GrokDefinition(name: "URIPATHPARAM", regex: #"%{URIPATH}(?:%{URIPARAM})?"#),
        GrokDefinition(name: "URI", regex: #"%{URIPROTO}://(?:%{USER}(?::[^@]*)?@)?(?:%{URIHOST})?(?:%{URIPATHPARAM})?"#),
        // Not among StreamSets' names: what COMMONAPACHELOG's Logstash body refers to.
        GrokDefinition(name: "HTTPDUSER", regex: #"%{EMAILADDRESS}|%{USER}"#),
        GrokDefinition(name: "EMAILADDRESS", regex: #"%{EMAILLOCALPART}@%{HOSTNAME}"#),
        GrokDefinition(name: "EMAILLOCALPART", regex: #"[a-zA-Z][a-zA-Z0-9_.+-=:]+"#),
    ]
}
