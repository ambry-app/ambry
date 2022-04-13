--
-- PostgreSQL database dump
--

-- Dumped from database version 13.4 (Debian 13.4-1.pgdg110+1)
-- Dumped by pg_dump version 13.6

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: citext; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS citext WITH SCHEMA public;


--
-- Name: EXTENSION citext; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION citext IS 'data type for case-insensitive character strings';


--
-- Name: oban_job_state; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.oban_job_state AS ENUM (
    'available',
    'scheduled',
    'executing',
    'retryable',
    'completed',
    'discarded',
    'cancelled'
);


ALTER TYPE public.oban_job_state OWNER TO postgres;

--
-- Name: oban_jobs_notify(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.oban_jobs_notify() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  channel text;
  notice json;
BEGIN
  IF NEW.state = 'available' THEN
    channel = 'public.oban_insert';
    notice = json_build_object('queue', NEW.queue);

    PERFORM pg_notify(channel, notice::text);
  END IF;

  RETURN NULL;
END;
$$;


ALTER FUNCTION public.oban_jobs_notify() OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: authors; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.authors (
    id bigint NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    name text NOT NULL,
    person_id bigint
);


ALTER TABLE public.authors OWNER TO postgres;

--
-- Name: authors_books; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.authors_books (
    id bigint NOT NULL,
    author_id bigint NOT NULL,
    book_id bigint NOT NULL
);


ALTER TABLE public.authors_books OWNER TO postgres;

--
-- Name: authors_books_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.authors_books_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.authors_books_id_seq OWNER TO postgres;

--
-- Name: authors_books_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.authors_books_id_seq OWNED BY public.authors_books.id;


--
-- Name: authors_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.authors_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.authors_id_seq OWNER TO postgres;

--
-- Name: authors_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.authors_id_seq OWNED BY public.authors.id;


--
-- Name: bookmarks; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.bookmarks (
    id bigint NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    media_id bigint NOT NULL,
    user_id bigint NOT NULL,
    "position" numeric NOT NULL,
    label text
);


ALTER TABLE public.bookmarks OWNER TO postgres;

--
-- Name: bookmarks_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.bookmarks_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.bookmarks_id_seq OWNER TO postgres;

--
-- Name: bookmarks_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.bookmarks_id_seq OWNED BY public.bookmarks.id;


--
-- Name: books; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.books (
    id bigint NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    title text NOT NULL,
    published date NOT NULL,
    image_path text,
    description text
);


ALTER TABLE public.books OWNER TO postgres;

--
-- Name: books_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.books_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.books_id_seq OWNER TO postgres;

--
-- Name: books_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.books_id_seq OWNED BY public.books.id;


--
-- Name: books_series; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.books_series (
    id bigint NOT NULL,
    book_id bigint NOT NULL,
    series_id bigint NOT NULL,
    book_number numeric NOT NULL
);


ALTER TABLE public.books_series OWNER TO postgres;

--
-- Name: books_series_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.books_series_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.books_series_id_seq OWNER TO postgres;

--
-- Name: books_series_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.books_series_id_seq OWNED BY public.books_series.id;


--
-- Name: media; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.media (
    id bigint NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    mpd_path text,
    book_id bigint NOT NULL,
    full_cast boolean DEFAULT false,
    status text DEFAULT 'pending'::text NOT NULL,
    abridged boolean NOT NULL,
    source_path text,
    mp4_path text,
    duration numeric,
    hls_path text,
    chapters jsonb
);


ALTER TABLE public.media OWNER TO postgres;

--
-- Name: media_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.media_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.media_id_seq OWNER TO postgres;

--
-- Name: media_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.media_id_seq OWNED BY public.media.id;


--
-- Name: media_narrators; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.media_narrators (
    id bigint NOT NULL,
    media_id bigint NOT NULL,
    narrator_id bigint NOT NULL
);


ALTER TABLE public.media_narrators OWNER TO postgres;

--
-- Name: media_narrators_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.media_narrators_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.media_narrators_id_seq OWNER TO postgres;

--
-- Name: media_narrators_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.media_narrators_id_seq OWNED BY public.media_narrators.id;


--
-- Name: narrators; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.narrators (
    id bigint NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    name text,
    person_id bigint
);


ALTER TABLE public.narrators OWNER TO postgres;

--
-- Name: narrators_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.narrators_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.narrators_id_seq OWNER TO postgres;

--
-- Name: narrators_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.narrators_id_seq OWNED BY public.narrators.id;


--
-- Name: oban_jobs; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.oban_jobs (
    id bigint NOT NULL,
    state public.oban_job_state DEFAULT 'available'::public.oban_job_state NOT NULL,
    queue text DEFAULT 'default'::text NOT NULL,
    worker text NOT NULL,
    args jsonb DEFAULT '{}'::jsonb NOT NULL,
    errors jsonb[] DEFAULT ARRAY[]::jsonb[] NOT NULL,
    attempt integer DEFAULT 0 NOT NULL,
    max_attempts integer DEFAULT 20 NOT NULL,
    inserted_at timestamp without time zone DEFAULT timezone('UTC'::text, now()) NOT NULL,
    scheduled_at timestamp without time zone DEFAULT timezone('UTC'::text, now()) NOT NULL,
    attempted_at timestamp without time zone,
    completed_at timestamp without time zone,
    attempted_by text[],
    discarded_at timestamp without time zone,
    priority integer DEFAULT 0 NOT NULL,
    tags character varying(255)[] DEFAULT ARRAY[]::character varying[],
    meta jsonb DEFAULT '{}'::jsonb,
    cancelled_at timestamp without time zone,
    CONSTRAINT attempt_range CHECK (((attempt >= 0) AND (attempt <= max_attempts))),
    CONSTRAINT positive_max_attempts CHECK ((max_attempts > 0)),
    CONSTRAINT priority_range CHECK (((priority >= 0) AND (priority <= 3))),
    CONSTRAINT queue_length CHECK (((char_length(queue) > 0) AND (char_length(queue) < 128))),
    CONSTRAINT worker_length CHECK (((char_length(worker) > 0) AND (char_length(worker) < 128)))
);


ALTER TABLE public.oban_jobs OWNER TO postgres;

--
-- Name: TABLE oban_jobs; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.oban_jobs IS '10';


--
-- Name: oban_jobs_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.oban_jobs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.oban_jobs_id_seq OWNER TO postgres;

--
-- Name: oban_jobs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.oban_jobs_id_seq OWNED BY public.oban_jobs.id;


--
-- Name: people; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.people (
    id bigint NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    name text,
    image_path text,
    description text
);


ALTER TABLE public.people OWNER TO postgres;

--
-- Name: people_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.people_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.people_id_seq OWNER TO postgres;

--
-- Name: people_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.people_id_seq OWNED BY public.people.id;


--
-- Name: player_states; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.player_states (
    id bigint NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    "position" numeric,
    playback_rate numeric,
    media_id bigint,
    user_id bigint,
    duration numeric,
    status text
);


ALTER TABLE public.player_states OWNER TO postgres;

--
-- Name: player_states_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.player_states_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.player_states_id_seq OWNER TO postgres;

--
-- Name: player_states_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.player_states_id_seq OWNED BY public.player_states.id;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.schema_migrations (
    version bigint NOT NULL,
    inserted_at timestamp(0) without time zone
);


ALTER TABLE public.schema_migrations OWNER TO postgres;

--
-- Name: series; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.series (
    id bigint NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    name text
);


ALTER TABLE public.series OWNER TO postgres;

--
-- Name: series_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.series_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.series_id_seq OWNER TO postgres;

--
-- Name: series_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.series_id_seq OWNED BY public.series.id;


--
-- Name: users; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.users (
    id bigint NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    email public.citext NOT NULL,
    hashed_password character varying(255) NOT NULL,
    confirmed_at timestamp(0) without time zone,
    admin boolean DEFAULT false
);


ALTER TABLE public.users OWNER TO postgres;

--
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.users_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.users_id_seq OWNER TO postgres;

--
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.users_id_seq OWNED BY public.users.id;


--
-- Name: users_tokens; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.users_tokens (
    id bigint NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    user_id bigint NOT NULL,
    token bytea NOT NULL,
    context character varying(255) NOT NULL,
    sent_to character varying(255)
);


ALTER TABLE public.users_tokens OWNER TO postgres;

--
-- Name: users_tokens_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.users_tokens_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.users_tokens_id_seq OWNER TO postgres;

--
-- Name: users_tokens_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.users_tokens_id_seq OWNED BY public.users_tokens.id;


--
-- Name: authors id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.authors ALTER COLUMN id SET DEFAULT nextval('public.authors_id_seq'::regclass);


--
-- Name: authors_books id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.authors_books ALTER COLUMN id SET DEFAULT nextval('public.authors_books_id_seq'::regclass);


--
-- Name: bookmarks id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.bookmarks ALTER COLUMN id SET DEFAULT nextval('public.bookmarks_id_seq'::regclass);


--
-- Name: books id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.books ALTER COLUMN id SET DEFAULT nextval('public.books_id_seq'::regclass);


--
-- Name: books_series id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.books_series ALTER COLUMN id SET DEFAULT nextval('public.books_series_id_seq'::regclass);


--
-- Name: media id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.media ALTER COLUMN id SET DEFAULT nextval('public.media_id_seq'::regclass);


--
-- Name: media_narrators id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.media_narrators ALTER COLUMN id SET DEFAULT nextval('public.media_narrators_id_seq'::regclass);


--
-- Name: narrators id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.narrators ALTER COLUMN id SET DEFAULT nextval('public.narrators_id_seq'::regclass);


--
-- Name: oban_jobs id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.oban_jobs ALTER COLUMN id SET DEFAULT nextval('public.oban_jobs_id_seq'::regclass);


--
-- Name: people id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.people ALTER COLUMN id SET DEFAULT nextval('public.people_id_seq'::regclass);


--
-- Name: player_states id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.player_states ALTER COLUMN id SET DEFAULT nextval('public.player_states_id_seq'::regclass);


--
-- Name: series id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.series ALTER COLUMN id SET DEFAULT nextval('public.series_id_seq'::regclass);


--
-- Name: users id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.users_id_seq'::regclass);


--
-- Name: users_tokens id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users_tokens ALTER COLUMN id SET DEFAULT nextval('public.users_tokens_id_seq'::regclass);


--
-- Data for Name: authors; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.authors (id, inserted_at, updated_at, name, person_id) FROM stdin;
1	2021-09-26 01:40:41	2021-09-26 01:40:41	Andy Weir	1
2	2021-09-26 01:40:41	2021-09-26 01:40:41	Becky Chambers	2
3	2021-09-26 01:40:41	2021-09-26 01:40:41	John Scalzi	3
4	2021-09-26 01:40:41	2021-09-26 01:40:41	Richard K. Morgan	4
5	2021-09-26 01:40:41	2021-09-26 01:40:41	Travis Bagwell	5
6	2021-09-26 01:40:41	2021-09-26 19:06:46	J.K. Rowling	12
7	2021-09-26 01:40:41	2021-09-26 19:06:46	Robert Galbraith	12
11	2021-09-28 01:37:24	2021-09-28 01:37:24	James S. A. Corey	15
13	2021-10-03 07:50:19	2021-10-03 07:50:19	test	18
14	2021-10-12 22:05:50	2021-10-12 22:05:50	Lev Grossman	19
15	2021-10-26 05:12:11	2021-10-26 05:12:11	H. G. Wells	21
22	2021-11-12 07:52:33	2021-11-12 07:52:33	Maureen Johnson	31
\.


--
-- Data for Name: authors_books; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.authors_books (id, author_id, book_id) FROM stdin;
1	1	12
2	4	1
3	5	3
4	5	11
5	5	14
6	5	6
7	5	2
8	5	4
9	5	16
10	5	5
11	5	7
12	5	9
13	5	8
14	3	10
15	2	13
16	2	15
17	6	17
18	6	18
19	6	19
20	6	20
21	6	21
22	6	22
23	6	23
24	7	24
25	7	25
26	7	26
27	7	27
28	7	28
34	11	39
37	14	41
38	15	42
43	15	49
44	22	50
45	1	51
46	11	52
47	3	52
\.


--
-- Data for Name: bookmarks; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.bookmarks (id, inserted_at, updated_at, media_id, user_id, "position", label) FROM stdin;
19	2021-11-03 02:02:21	2021-11-03 02:02:28	39	1	2430.659898	Beginning
13	2021-11-03 01:56:49	2021-11-03 02:02:38	39	1	59104.727047	JANE!?
20	2021-11-03 02:02:47	2021-11-03 02:02:49	39	1	30788.358714	Middle
24	2021-11-03 02:06:31	2021-11-03 02:06:35	39	1	16111.493532	Fire!
25	2021-11-03 02:11:38	2021-11-03 02:11:57	39	1	48883.149804	This is a really long description, so we can see what it does to the bookmarks table. I hope it looks ok...
26	2021-11-04 03:06:07	2021-11-04 03:11:24	39	1	1234.56	cool
29	2021-11-05 02:03:51	2021-11-05 02:03:58	39	1	29.436743	Book 1
28	2021-11-05 02:03:18	2021-11-05 02:04:03	39	1	61951.853835	Near the end
30	2021-11-05 02:04:19	2021-11-05 02:04:21	39	1	21469.89567	???
31	2021-11-05 02:04:34	2021-11-05 02:04:40	39	1	47710.879266	Something something something...
32	2021-11-05 02:04:46	2021-11-05 02:04:51	39	1	26891.586496	need more bookmarks
33	2021-11-05 02:04:57	2021-11-05 02:04:59	39	1	42867.502129	dunzo
34	2021-11-05 02:19:59	2021-11-05 02:20:02	39	1	8096.391633	...
35	2021-11-05 02:20:06	2021-11-05 02:20:10	39	1	6650.607413	...
36	2021-11-05 02:20:15	2021-11-05 02:20:20	39	1	60072.334349	...
37	2021-11-05 02:20:27	2021-11-05 02:20:37	39	1	18578.327229	Another big one goes here. Another big one goes here. Another big one goes here. Another big one goes here. Another big one goes here. 
38	2021-11-13 06:20:17	2021-11-13 06:20:28	43	1	31.331405	Test
40	2022-02-15 02:56:04	2022-02-15 02:56:04	83	1	5329.494291	\N
39	2022-02-15 02:28:17	2022-02-15 17:28:38	83	1	61.274584	Foo!
\.


--
-- Data for Name: books; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.books (id, inserted_at, updated_at, title, published, image_path, description) FROM stdin;
1	2021-09-26 01:40:41	2021-09-26 01:40:41	Altered Carbon	2002-02-28	/uploads/images/altered_carbon.jpg	Four hundred years from now mankind is strung out across a region of interstellar space inherited from an ancient civilization discovered on Mars. The colonies are linked together by the occasional sublight colony ship voyages and hyperspatial data-casting. Human consciousness is digitally freighted between the stars and downloaded into bodies as a matter of course.\n\nBut some things never change. So when ex-envoy, now-convict Takeshi Kovacs has his consciousness and skills downloaded into the body of a nicotine-addicted ex-thug and presented with a catch-22 offer, he really shouldn't be surprised. Contracted by a billionaire to discover who murdered his last body, Kovacs is drawn into a terrifying conspiracy that stretches across known space and to the very top of society.\n
2	2021-09-26 01:40:41	2021-09-26 01:40:41	Apathy	2018-07-26	/uploads/images/apathy.jpg	**A side quest adventure in the best-selling world of Awaken Online!**\n\nEliza's parents are relentless - forcing her to constantly take extra courses to prepare for college and medical school. Sometimes, it feels like her entire life has already been planned out.\n\nWhich is why she leaps at the chance to escape into a new virtual reality game, Awaken Online. What she wasn't expecting was to encounter a capricious god and his loyal "pet." Or to be chosen as this god's "avatar" within the game and forced to tackle a series of asinine quests.\n\nYet, she just can't shake the feeling that there is more to the irritating god than first meets the eye.\n
3	2021-09-26 01:40:41	2021-09-26 01:40:41	Catharsis	2016-07-23	/uploads/images/catharsis.jpg	Jason logs into Awaken Online fed-up with reality. He's in desperate need of an escape, and this game is his ticket to finally feeling the type of power and freedom that are so sorely lacking in his real life.\n\nAwaken Online is a brand new virtual reality game that just hit the market, promising an unprecedented level of immersion. Yet Jason quickly finds himself pushed down a path he didn't expect. In this game, he isn't the hero. There are no damsels to save. There are no bad guys to vanquish.\n\nIn fact, he might just be the villain.\n
4	2021-09-26 01:40:41	2021-09-26 01:40:41	Dominion	2019-02-26	/uploads/images/dominion.jpg	**The fourth installment in the best selling Awaken Online series!**\n\nFollowing Jason's evolution into a Keeper, he finds his fledgling city once again in turmoil. A new and deadly enemy threatens the Twilight Throne -- one that has no difficulty contending with Jason and the members of Original Sin.\n\nJason must work quickly to consolidate his city's power. That means securing the villages within the Twilight Throne's influence, finding a steady stream of income, and growing the city's military strength. Even as the group grapples with these changes, they notice that something is stirring up the native undead around the city, although the source of this strange influence is uncertain.\n\nOne thing is clear, however. Jason might have evolved, but his enemies have adapted with him. If the Twilight Throne is to survive, the group must grow stronger and Jason must learn to control his newfound abilities.\n\nOtherwise, the darkness may very well claim them all.\n
5	2021-09-26 01:40:41	2021-09-26 01:40:41	Ember	2019-11-01	/uploads/images/ember.jpg	**Desert sands. Arcane magic. A love lost.**\n\nFinn Harris should have been the one to die.\n\nBut he wasn't - his wife took his place. What was worse, he only had himself and his company to blame. They let their passion outpace their prudence, determined to revolutionize the world. While all innovation comes with a price, he never imagined it would cost him Rachael.\n\nNearly a decade later, Finn is content to hole himself up and wait out the rest of his life - what little he has left. That is, until his daughter intervenes, forcing him out of his grief and into a new virtual reality game developed by his old employer. They're calling it Awaken Online, and she believes there's something unusual going on inside the game. And since Finn knows the company, knows their tactics - she might be right.\n\nFinn wasn't sure what he expected to find when he logged in. But it certainly wasn't a manipulative fire god or a school for mages - where the students are pitted against each other in deadly duels and the faculty isn't shy about maiming or injuring novice mages to prove a point.\n\nNow Finn must learn to fight, for his own life and a chance at redemption. He'll need to prove that his fire hasn't been snuffed out.\n\nThat there's still an ember burning...\n
6	2021-09-26 01:40:41	2021-09-26 01:40:41	Evolution	2018-05-23	/uploads/images/evolution.jpg	After exiting Awaken Online to find himself holding a knife and standing over two dead bodies, Jason is now being investigated for murder. To make matters worse, Claire has stumbled upon evidence of Alfred's involvement in the incident and the CPSC is circling - just waiting for Cerillion Entertainment to make a mistake.\n\nWith his real-life in shambles and his enemies in-game growing in strength, Jason re-enters Awaken Online truly desperate - the game now his only lifeline. He will need to move quickly to complete the Old Man's quest and to obtain the power he was promised.\n
7	2021-09-26 01:40:41	2021-09-26 01:40:41	Flame	2020-04-01	/uploads/images/flame.jpg	**Deadly competition. Deep desert. A dying tyrant.**\n\nFinn Harris was declared the Mage Guild’s champion.\n\nHowever, that was only the beginning of the Emir’s competition. The next stage will send Finn and his companions deep into the desert north of Lahab in search of a long-lost relic. The magical artifact is said to be held within the Abyss.\n\nExcept, this time, he’s not just facing novice mages. Everyone in the region seems to be arrayed against him, god and man alike. Racing against the other two champions, swept into the middle of a conflict between the Emir and those he’s wronged, and at the mercy of a manipulative fire goddess, Finn must battle his way through the Abyss and claim his prize.\n\nYet he will not stop, and he cannot afford to fail – not with Rachael’s life hanging in the balance.\n\nHe will need to embrace his gifts and overcome his past.\n\nFinn will need to become a true prophet of the flame.\n
8	2021-09-26 01:40:41	2021-09-26 01:40:41	Hellion	2021-05-01	/uploads/images/hellion.jpg	**Jason's back! And he's ready for some revenge!**\n\nRoughly a month has passed in-game since Thorn's attack on the Twilight Throne. In that time, the dark city has managed to recover and rebuild - growing the ranks of Original Sin at the same time.\n\nWhich is good, because that brief respite is over. The Avatar of Flame has risen within the depths of the northern desert and has thrown down a digital gauntlet to Jason - with a gate piece hanging in the balance. Even worse? His opponent is none other than Finn Harris, the 'father of modern AI.' The same man that may have been behind Thorn's attack on the Twilight Throne.\n\nAnd in the wake of recent events - the committee hearing back in the real world and the attack on his people - Jason is no longer content to just react; to wallow in the safety of his kingdom. If he's to be painted the villain... well, then it's long past time he fully embraced that role.\n\nBecause now it's personal.\n\nAnd there'll be no holding back...\n
9	2021-09-26 01:40:41	2021-09-26 01:40:41	Inferno	2020-10-03	/uploads/images/inferno.jpg	**The epic conclusion of the Tarot series!**\n\nA crippling wound. A war looming on the horizon. A demon king to kill.\n\nFinn and his companions barely escaped their encounter with Bilel. But not without a cost - including the loss of Finn's left arm and the magical corruption that now plagues his body.\n\nDespite those handicaps, Finn must keep pressing forward if he is to have any hope of bringing Rachael back. As the Seer predicted, the guilds and Khamsin have formed a fragile alliance. But before they can lay siege to Lahab, Finn and his companions must first find a way to defend themselves and their fledgling army from the effects of the god relic that Bilel now wields...\n\nWhich will send them deep into the heart of an ancient workshop. Along the way, they'll encounter advanced magical technology, new friends and foes, and will be pushed well beyond their limits. They will be reforged in the fires of adversity - forced to prove their mettle, even with the odds stacked against them.\n\nHopefully, it will be enough.\n\nBecause soon they will face a demon king and his armies.\n
10	2021-09-26 01:40:41	2021-09-26 01:40:41	Lock In	2014-08-26	/uploads/images/lock_in.jpg	Not too long from today, a new, highly contagious virus makes its way across the globe. Most who get sick experience nothing worse than flu, fever and headaches. But for the unlucky one percent - and nearly five million souls in the United States alone - the disease causes "Lock In": Victims fully awake and aware, but unable to move or respond to stimulus. The disease affects young, old, rich, poor, people of every color and creed. The world changes to meet the challenge.\n\nA quarter of a century later, in a world shaped by what's now known as "Haden's syndrome," rookie FBI agent Chris Shane is paired with veteran agent Leslie Vann. The two of them are assigned what appears to be a Haden-related murder at the Watergate Hotel, with a suspect who is an "integrator" - someone who can let the locked in borrow their bodies for a time. If the Integrator was carrying a Haden client, then naming the suspect for the murder becomes that much more complicated.\n\nBut "complicated" doesn't begin to describe it. As Shane and Vann began to unravel the threads of the murder, it becomes clear that the real mystery - and the real crime - is bigger than anyone could have imagined. The world of the locked in is changing, and with the change comes opportunities that the ambitious will seize at any cost. The investigation that began as a murder case takes Shane and Vann from the halls of corporate power to the virtual spaces of the locked in, and to the very heart of an emerging, surprising new human culture. It's nothing you could have expected.\n
19	2021-09-26 01:40:41	2021-09-26 01:40:41	Harry Potter and the Prisoner of Azkaban	1999-07-08	/uploads/images/harry3.jpg	For twelve long years, the dread fortress of Azkaban held an infamous prisoner named Sirius Black. Convicted of killing thirteen people with a single curse, he was said to be the heir apparent to the Dark Lord, Voldemort.\n\nNow he has escaped, leaving only two clues as to where he might be headed: Harry Potter's defeat of You-Know-Who was Black's downfall as well. And the Azkaban guards heard Black muttering in his sleep, "He's at Hogwarts . . . he's at Hogwarts."\n\nHarry Potter isn't safe, not even within the walls of his magical school, surrounded by his friends. Because on top of it all, there may well be a traitor in their midst.\n
20	2021-09-26 01:40:41	2021-09-26 01:40:41	Harry Potter and the Goblet of Fire	2000-07-08	/uploads/images/harry4.jpg	Harry Potter is midway through his training as a wizard and his coming of age. Harry wants to get away from the pernicious Dursleys and go to the International Quidditch Cup with Hermione, Ron, and the Weasleys. He wants to dream about Cho Chang, his crush (and maybe do more than dream). He wants to find out about the mysterious event that's supposed to take place at Hogwarts this year, an event involving two other rival schools of magic, and a competition that hasn't happened for hundreds of years. He wants to be a normal, fourteen-year-old wizard. But unfortunately for Harry Potter, he's not normal - even by wizarding standards.\n\nAnd in his case, different can be deadly.\n
11	2021-09-26 01:40:41	2021-09-26 01:40:41	Precipice	2017-03-26	/uploads/images/precipice.jpg	A few days have passed since Jason's confrontation with Alfred and he's debating whether to reenter Awaken Online. Alfred has made a proposition that Jason isn't certain he should accept.\n\nAfter the battle with Alexion, Jason has also been appointed the Regent of the Twilight Throne. He must assume the mantle of ruling an undead city – with everything that entails. His first task is to investigate the dark keep that looms over the city’s marketplace. This act will lead to a chain of events that might ensure his city’s survival or create new enemies.\n\nMeanwhile, Alex re-enters the game listless and angry after his loss against Jason. With his reputation in the gutter and no prospects, he will face a choice regarding how he intends to blaze his path through the game.\n
21	2021-09-26 01:40:41	2021-09-26 01:40:41	Harry Potter and the Order of the Phoenix	2003-06-21	/uploads/images/harry5.jpg	There is a door at the end of a silent corridor. And it’s haunting Harry Pottter’s dreams. Why else would he be waking in the middle of the night, screaming in terror?\n\nHarry has a lot on his mind for this, his fifth year at Hogwarts: a Defense Against the Dark Arts teacher with a personality like poisoned honey; a big surprise on the Gryffindor Quidditch team; and the looming terror of the Ordinary Wizarding Level exams. But all these things pale next to the growing threat of He-Who-Must-Not-Be-Named - a threat that neither the magical government nor the authorities at Hogwarts can stop.\n\nAs the grasp of darkness tightens, Harry must discover the true depth and strength of his friends, the importance of boundless loyalty, and the shocking price of unbearable sacrifice.\n\nHis fate depends on them all.\n
12	2021-09-26 01:40:41	2021-09-26 01:40:41	Project Hail Mary	2021-05-04	/uploads/images/project_hail_mary.jpg	Ryland Grace is the sole survivor on a desperate, last-chance mission--and if he fails, humanity and the earth itself will perish.\n\nExcept that right now, he doesn't know that. He can't even remember his own name, let alone the nature of his assignment or how to complete it.\n\nAll he knows is that he's been asleep for a very, very long time. And he's just been awakened to find himself millions of miles from home, with nothing but two corpses for company.\n\nHis crewmates dead, his memories fuzzily returning, he realizes that an impossible task now confronts him. Alone on this tiny ship that's been cobbled together by every government and space agency on the planet and hurled into the depths of space, it's up to him to conquer an extinction-level threat to our species.\n\nAnd thanks to an unexpected ally, he just might have a chance.\n\nPart scientific mystery, part dazzling interstellar journey, Project Hail Mary is a tale of discovery, speculation, and survival to rival The Martian--while taking us to places it never dreamed of going.\n
22	2021-09-26 01:40:41	2021-09-26 01:40:41	Harry Potter and the Half-Blood Prince	2005-07-16	/uploads/images/harry6.jpg	The war against Voldemort is not going well; even Muggle governments are noticing. Ron scans the obituary pages of the Daily Prophet, looking for familiar names. Dumbledore is absent from Hogwarts for long stretches of time, and the Order of the Phoenix has already suffered losses.\n\nAnd yet . . .\n\nAs in all wars, life goes on. The Weasley twins expand their business. Sixth-year students learn to Apparate - and lose a few eyebrows in the process. Teenagers flirt and fight and fall in love. Classes are never straightforward, through Harry receives some extraordinary help from the mysterious Half-Blood Prince.\n\nSo it's the home front that takes center stage in the multilayered sixth installment of the story of Harry Potter. Here at Hogwarts, Harry will search for the full and complete story of the boy who became Lord Voldemort - and thereby find what may be his only vulnerability.\n
13	2021-09-26 01:40:41	2021-09-26 01:40:41	Record of a Spaceborn Few	2018-07-24	/uploads/images/record_of_a_spaceborn_few.jpg	Centuries after the last humans left Earth, the Exodus Fleet is a living relic, a place many are from but few outsiders have seen. Humanity has finally been accepted into the galactic community, but while this has opened doors for many, those who have not yet left for alien cities fear that their carefully cultivated way of life is under threat.\n\nTessa chose to stay home when her brother Ashby left for the stars, but has to question that decision when her position in the Fleet is threatened.\n\nKip, a reluctant young apprentice, itches for change but doesn't know where to find it.\n\nSawyer, a lost and lonely newcomer, is just looking for a place to belong.\n\nWhen a disaster rocks this already fragile community, those Exodans who still call the Fleet their home can no longer avoid the inescapable question:\n\nWhat is the purpose of a ship that has reached its destination?\n
23	2021-09-26 01:40:41	2021-09-26 01:40:41	Harry Potter and the Deathly Hallows	2007-07-21	/uploads/images/harry7.jpg	It's no longer safe for Harry at Hogwarts, so he and his best friends, Ron and Hermione, are on the run. Professor Dumbledore has given them clues about what they need to do to defeat the dark wizard, Lord Voldemort, once and for all, but it's up to them to figure out what these hints and suggestions really mean. Their cross-country odyssey has them searching desperately for the answers, while evading capture or death at every turn. At the same time, their friendship, fortitude, and sense of right and wrong are tested in ways they never could have imagined. The ultimate battle between good and evil that closes out this final chapter of the epic series takes place where Harry's Wizarding life began: at Hogwarts. The satisfying conclusion offers shocking last-minute twists, incredible acts of courage, powerful new forms of magic, and the resolution of many mysteries. Above all, this intense, cathartic book serves as a clear statement of the message at the heart of the Harry Potter series: that choice matters much more than destiny, and that love will always triumph over death.\n
14	2021-09-26 01:40:41	2021-09-26 01:40:41	Retribution	2017-10-31	/uploads/images/retribution.jpg	A side quest adventure in the same world as the best-selling Awaken Online series. This story takes place after the end of Awaken Online: Precipice.\n\nRiley’s real-life took a nosedive after her confrontation with Alex. The girls at school torment her and she feels powerless to do anything about it. At the same time, Jason has mysteriously disappeared, sending only a terse cryptic message to Riley and Frank.\n\nWith some time on her hands and with her frustration with her real-life reaching a breaking point, Riley decides to strike off on her own in-game. Her goal is to investigate the quest related to the strange bow she discovered in the dungeon north of Peccavi. Yet events quickly spiral out of control as she discovers that the bow’s former owner has set her along a path of vengeance – with an entire city hanging in the balance.\n
24	2021-09-26 01:40:41	2021-09-26 01:40:41	The Cuckoo's Calling	2013-04-18	/uploads/images/strike1.jpg	After losing his leg to a land mine in Afghanistan, Cormoran Strike is barely scraping by as a private investigator. Then John Bristow walks through his door with an amazing story: His sister, the legendary supermodel Lula Landry, famously fell to her death a few months earlier. The police ruled it a suicide, but John refuses to believe that. The case plunges Strike into the world of multimillionaire beauties, rock-star boyfriends, and desperate designers, and it introduces him to every variety of pleasure, enticement, seduction, and delusion known to man.\n
15	2021-09-26 01:40:41	2021-09-26 01:40:41	To Be Taught, If Fortunate	2019-08-08	/uploads/images/to_be_taught_if_fortunate.jpg	In her new novella, Sunday Times best-selling author Becky Chambers imagines a future in which, instead of terraforming planets to sustain human life, explorers of the solar system instead transform themselves.\n\nAriadne is one such explorer. As an astronaut on an extrasolar research vessel, she and her fellow crewmates sleep between worlds and wake up each time with different features. Her experience is one of fluid body and stable mind and of a unique perspective on the passage of time. Back on Earth, society changes dramatically from decade to decade, as it always does.\n\nAriadne may awaken to find that support for space exploration back home has waned, or that her country of birth no longer exists, or that a cult has arisen around their cosmic findings, only to dissolve once more by the next waking. But the moods of Earth have little bearing on their mission: to explore, to study, and to send their learnings home.\n\nCarrying all the trademarks of her other beloved works, including brilliant writing, fantastic world-building and exceptional, diverse characters, Becky's first audiobook outside of the Wayfarers series is sure to capture the imagination of listeners all over the world.\n
25	2021-09-26 01:40:41	2021-09-26 01:40:41	The Silkworm	2014-06-19	/uploads/images/strike2.jpg	When novelist Owen Quine goes missing, his wife calls in private detective Cormoran Strike. At first, Mrs. Quine just thinks her husband has gone off by himself for a few days—as he has done before—and she wants Strike to find him and bring him home.\n\nBut as Strike investigates, it becomes clear that there is more to Quine's disappearance than his wife realizes. The novelist has just completed a manuscript featuring poisonous pen-portraits of almost everyone he knows. If the novel were to be published, it would ruin lives—meaning that there are a lot of people who might want him silenced.\n\nWhen Quine is found brutally murdered under bizarre circumstances, it becomes a race against time to understand the motivation of a ruthless killer, a killer unlike any Strike has encountered before...\n
16	2021-09-26 01:40:41	2021-09-26 01:40:41	Unity	2019-06-18	/uploads/images/unity.jpg	**A side quest adventure in the best selling world of Awaken Online!**\n\nIn the aftermath of Thorn's attack on the Twilight Throne, Frank is in an awkward position. Jason and Riley have outpaced him and everyone is hard at work rebuilding the Twilight Throne, establishing new towns, and trying to get their fledgling manufacturing operation off the ground. Everyone except Frank - who finds himself with no immediate task or goal.\n\nSo Frank decides to strike off on his own. He sets his eyes on the north, heading toward the snow-capped mountains that loom over the undead kingdom's border in the hope of improving his shapeshifting abilities.\n\nHe soon stumbles into an unexpected adventure. A journey that may unearth the secrets behind his class and finally force him to reach his true potential.\n
26	2021-09-26 01:40:41	2021-09-26 01:40:41	Career of Evil	2015-10-20	/uploads/images/strike3.jpg	When a mysterious package is delivered to Robin Ellacott, she is horrified to discover that it contains a woman’s severed leg.\n\nHer boss, private detective Cormoran Strike, is less surprised but no less alarmed. There are four people from his past who he thinks could be responsible – and Strike knows that any one of them is capable of sustained and unspeakable brutality.\n\nWith the police focusing on the one suspect Strike is increasingly sure is not the perpetrator, he and Robin take matters into their own hands, and delve into the dark and twisted worlds of the other three men. But as more horrendous acts occur, time is running out for the two of them…\n\nCareer of Evil is the third in the series featuring private detective Cormoran Strike and his assistant Robin Ellacott. A mystery and also a story of a man and a woman at a crossroads in their personal and professional lives.\n
17	2021-09-26 01:40:41	2021-09-26 01:40:41	Harry Potter and the Sorcerer's Stone	1997-06-26	/uploads/images/harry1.jpg	Harry Potter's life is miserable. His parents are dead and he's stuck with his heartless relatives, who force him to live in a tiny closet under the stairs. But his fortune changes when he receives a letter that tells him the truth about himself: he's a wizard. A mysterious visitor rescues him from his relatives and takes him to his new home, Hogwarts School of Witchcraft and Wizardry.\n\nAfter a lifetime of bottling up his magical powers, Harry finally feels like a normal kid. But even within the Wizarding community, he is special. He is the boy who lived: the only person to have ever survived a killing curse inflicted by the evil Lord Voldemort, who launched a brutal takeover of the Wizarding world, only to vanish after failing to kill Harry.\n\nThough Harry's first year at Hogwarts is the best of his life, not everything is perfect. There is a dangerous secret object hidden within the castle walls, and Harry believes it's his responsibility to prevent it from falling into evil hands. But doing so will bring him into contact with forces more terrifying than he ever could have imagined.\n\nFull of sympathetic characters, wildly imaginative situations, and countless exciting details, the first installment in the series assembles an unforgettable magical world and sets the stage for many high-stakes adventures to come.\n
27	2021-09-26 01:40:41	2021-09-26 01:40:41	Lethal White	2018-09-18	/uploads/images/strike4.jpg	When Billy, a troubled young man, comes to private eye Cormoran Strike's office to ask for his help investigating a crime he thinks he witnessed as a child, Strike is left deeply unsettled. While Billy is obviously mentally distressed, and cannot remember many concrete details, there is something sincere about him and his story. But before Strike can question him further, Billy bolts from his office in a panic.\n\nTrying to get to the bottom of Billy's story, Strike and Robin Ellacott — once his assistant, now a partner in the agency — set off on a twisting trail that leads them through the backstreets of London, into a secretive inner sanctum within Parliament, and to a beautiful but sinister manor house deep in the countryside.\n\nAnd during this labyrinthine investigation, Strike's own life is far from straightforward: his newfound fame as a private eye means he can no longer operate behind the scenes as he once did. Plus, his relationship with his former assistant is more fraught than it ever has been — Robin is now invaluable to Strike in the business, but their personal relationship is much, much trickier than that.\n\nThe most epic Robert Galbraith novel yet, Lethal White is both a gripping mystery and a page-turning next instalment in the ongoing story of Cormoran Strike and Robin Ellacott.\n
18	2021-09-26 01:40:41	2021-09-26 01:40:41	Harry Potter and the Chamber of Secrets	1998-07-02	/uploads/images/harry2.jpg	The Dursleys were so mean and hideous that summer that all Harry Potter wanted was to get back to the Hogwarts School for Witchcraft and Wizardry. But just as he's packing his bags, Harry receives a warning from a strange, impish creature named Dobby who says that if Harry Potter returns to Hogwarts, disaster will strike.\n\nAnd strike it does. For in Harry's second year at Hogwarts, fresh torments and horrors arise, including an outrageously stuck-up new professor, Gilderoy Lockhart, a spirit named Moaning Myrtle who haunts the girls' bathroom, and the unwanted attentions of Ron Weasley's younger sister, Ginny. But each of these seem minor annoyances when the real trouble begins, and someone, or something, starts turning Hogwarts students to stone. Could it be Draco Malfoy, a more poisonous rival than ever? Could it possibly be Hagrid, whose mysterious past is finally told? Or could it be the one everyone at Hogwarts most suspects: Harry Potter himself?\n
28	2021-09-26 01:40:41	2021-09-26 01:40:41	Troubled Blood	2020-09-15	/uploads/images/strike5.jpg	Private Detective Cormoran Strike is visiting his family in Cornwall when he is approached by a woman asking for help finding her mother, Margot Bamborough — who went missing in mysterious circumstances in 1974.\n\nStrike has never tackled a cold case before, let alone one forty years old. But despite the slim chance of success, he is intrigued and takes it on; adding to the long list of cases that he and his partner in the agency, Robin Ellacott, are currently working on. And Robin herself is also juggling a messy divorce and unwanted male attention, as well as battling her own feelings about Strike.\n\nAs Strike and Robin investigate Margot's disappearance, they come up against a fiendishly complex case with leads that include tarot cards, a psychopathic serial killer and witnesses who cannot all be trusted. And they learn that even cases decades old can prove to be deadly . . .\n
41	2021-10-12 22:06:45	2021-10-12 22:11:03	The Magicians	2009-08-11	/uploads/images/e9e40f629f84ba647814d6d1761fad72.jpg	\N
42	2021-10-26 05:12:49	2021-10-26 05:12:49	The War of the Worlds	1900-01-01	/uploads/images/ba7a1c27e1e327b3addc25187633d70a.jpg	\N
49	2021-10-28 03:04:30	2021-10-28 03:04:30	The Time Machine	1895-01-01	/uploads/images/d77fb172652afdb998f53b40e3ffabf9.png	\N
50	2021-11-12 07:53:52	2021-11-12 07:53:52	The Box in the Woods	2021-06-15	/uploads/images/3b6ae0de5491462af4f135de33400a7b.jpg	**The Truly Devious series continues as Stevie Bell investigates her first mystery outside of Ellingham Academy in this spine-chilling and hilarious stand-alone mystery.**\n\nAmateur sleuth Stevie Bell needs a good murder. After catching a killer at her high school, she’s back at home for a normal (that means boring) summer.\n\nBut then she gets a message from the owner of Sunny Pines, formerly known as Camp Wonder Falls—the site of the notorious unsolved case, the Box in the Woods Murders. Back in 1978, four camp counselors were killed in the woods outside of the town of Barlow Corners, their bodies left in a gruesome display. The new owner offers Stevie an invitation: Come to the camp and help him work on a true crime podcast about the case.\n\nStevie agrees, as long as she can bring along her friends from Ellingham Academy. Nothing sounds better than a summer spent together, investigating old murders.\n\nBut something evil still lurks in Barlow Corners. When Stevie opens the lid on this long-dormant case, she gets much more than she bargained for. The Box in the Woods will make room for more victims. This time, Stevie may not make it out alive.
51	2021-11-27 01:08:24	2021-11-27 01:08:24	test	0001-01-01	/uploads/images/62a532ae04b9192de6ec426d25d522b0.jpg	test
39	2021-09-28 01:39:42	2021-09-28 01:39:42	Cibola Burn	2014-06-05	/uploads/images/d67c69b85c04507d64707262be7c53f7.jpg	**The fourth novel in James S.A. Corey’s New York Times bestselling Expanse series**\n\nThe gates have opened the way to thousands of habitable planets, and the land rush has begun. Settlers stream out from humanity's home planets in a vast, poorly controlled flood, landing on a new world. Among them, the Rocinante, haunted by the vast, posthuman network of the protomolecule as they investigate what destroyed the great intergalactic society that built the gates and the protomolecule.\n\nBut Holden and his crew must also contend with the growing tensions between the settlers and the company which owns the official claim to the planet. Both sides will stop at nothing to defend what's theirs, but soon a terrible disease strikes and only Holden - with help from the ghostly Detective Miller - can find the cure.
52	2021-11-27 21:42:02	2022-02-19 04:44:15	This is a Book Title	0001-01-01	/uploads/images/62a532ae04b9192de6ec426d25d522b0.jpg	test2
\.


--
-- Data for Name: books_series; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.books_series (id, book_id, series_id, book_number) FROM stdin;
1	1	1	1
2	3	2	1
3	11	2	2
4	14	2	2.5
5	6	2	3
6	2	2	3.5
7	4	2	4
8	16	2	4.5
9	5	2	4.6
10	7	2	4.7
11	9	2	4.8
12	8	2	5
13	5	3	1
14	7	3	2
16	10	4	1
17	13	5	3
18	17	6	1
19	18	6	2
20	19	6	3
21	20	6	4
22	21	6	5
23	22	6	6
24	23	6	7
25	24	7	1
26	25	7	2
27	26	7	3
28	27	7	4
29	28	7	5
30	9	3	3
34	39	9	4
40	41	10	1
54	50	15	4
55	52	2	1
56	52	6	4
\.


--
-- Data for Name: media; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.media (id, inserted_at, updated_at, mpd_path, book_id, full_cast, status, abridged, source_path, mp4_path, duration, hls_path, chapters) FROM stdin;
38	2021-10-26 05:22:12	2021-11-12 06:25:06	/uploads/media/46968c25-c0af-4585-849d-f31a8f397395.mpd	42	f	ready	f	/home/chris/src/ambry/uploads/source_media/eab1112c-3a35-4b62-adde-b7b1f2989c49	/uploads/media/46968c25-c0af-4585-849d-f31a8f397395.mp4	23361.828571	/uploads/media/46968c25-c0af-4585-849d-f31a8f397395.m3u8	[{"time": "0.00", "title": "01 - The Eve of War"}, {"time": "897.01", "title": "02 - The Falling Star"}, {"time": "1412.02", "title": "03 - On Horsell Common"}, {"time": "1803.00", "title": "04 - The Cylinder Opens"}, {"time": "2251.02", "title": "05 - The Heat-Ray"}, {"time": "2817.01", "title": "06 - The Heat-Ray in the Chobham Road"}, {"time": "3146.02", "title": "07 - How I Reached Home"}, {"time": "3653.02", "title": "08 - Friday Night"}, {"time": "4040.02", "title": "09 - The Fighting Begins"}, {"time": "4799.01", "title": "10 - In the Storm"}, {"time": "5652.02", "title": "11 - At the Window"}, {"time": "6449.01", "title": "12 - What I Saw of the Destruction of Weybridge and Shepperton"}, {"time": "7933.00", "title": "13 - How I Fell in with the Curate"}, {"time": "8642.01", "title": "14 - In London"}, {"time": "10102.01", "title": "15 - What had happened in Surrey"}, {"time": "11199.00", "title": "16 - The Exodus from London"}, {"time": "12762.02", "title": "17 - The \\"Thunder Child\\""}, {"time": "13993.01", "title": "18 - Under Foot"}, {"time": "14980.02", "title": "19 - What we saw from the Ruined House"}, {"time": "16325.02", "title": "20 - The Days of Imprisonment"}, {"time": "17088.01", "title": "21 - The Death of the Curate"}, {"time": "17743.01", "title": "22 - The Stillness"}, {"time": "18137.00", "title": "23 - The Work of Fifteen Days"}, {"time": "18637.01", "title": "24 - The Man on Putney Hill"}, {"time": "20806.00", "title": "25 - Dead London"}, {"time": "22075.00", "title": "26 - Wreckage"}, {"time": "22813.01", "title": "27 - The Epilogue"}]
46	2021-11-12 07:54:32	2021-11-13 01:40:01	/uploads/media/5eec12c4-692e-4494-8067-8569db469994.mpd	50	f	ready	f	/home/chris/src/ambry/uploads/source_media/3c088568-ae5c-4f35-8a9c-f5105615a229	/uploads/media/5eec12c4-692e-4494-8067-8569db469994.mp4	33171.598844	/uploads/media/5eec12c4-692e-4494-8067-8569db469994.m3u8	[{"time": "0.00", "title": "The Box in the Woods"}, {"time": "14.00", "title": "Epigraph"}, {"time": "34.00", "title": "July 6, 1978 11:45 p.m."}, {"time": "1251.00", "title": "“THE STUDENT SLEUTH OF ELLINGHAM ACADEMY” By Germaine Batt"}, {"time": "1396.00", "title": "Chapter 1"}, {"time": "2182.00", "title": "July 7, 1978 7:30 a.m."}, {"time": "2656.00", "title": "Chapter 2"}, {"time": "3266.00", "title": "July 7, 1978 7:30 a.m."}, {"time": "3841.69", "title": "Chapter 3"}, {"time": "5200.69", "title": "July 7, 1978 8:05 a.m"}, {"time": "5802.69", "title": "Chapter 4"}, {"time": "6802.69", "title": "Chapter 5"}, {"time": "7547.69", "title": "Chapter 6"}, {"time": "8499.21", "title": "July 11, 1978 6:00 p.m."}, {"time": "9140.21", "title": "Chapter 7"}, {"time": "10106.21", "title": "Chapter 8"}, {"time": "11174.21", "title": "Chapter 9"}, {"time": "11989.21", "title": "July 11, 1978 9:30 p.m."}, {"time": "12507.04", "title": "Chapter 10"}, {"time": "13305.04", "title": "Chapter 11"}, {"time": "14499.04", "title": "Chapter 12"}, {"time": "15436.04", "title": "Chapter 13"}, {"time": "16354.04", "title": "Chapter 14"}, {"time": "16941.27", "title": "Chapter 15"}, {"time": "17692.27", "title": "Chapter 16"}, {"time": "18861.27", "title": "Chapter 17"}, {"time": "19485.27", "title": "Chapter 18"}, {"time": "20281.27", "title": "Chapter 19"}, {"time": "21076.37", "title": "Chapter 20"}, {"time": "22614.37", "title": "Chapter 21"}, {"time": "23669.37", "title": "Chapter 22"}, {"time": "24583.37", "title": "Chapter 23"}, {"time": "25477.50", "title": "Chapter 24"}, {"time": "26559.50", "title": "Chapter 25"}, {"time": "27651.50", "title": "Chapter 26"}, {"time": "28191.50", "title": "Chapter 27"}, {"time": "29031.48", "title": "Chapter 28"}, {"time": "31057.48", "title": "Chapter 29"}, {"time": "32654.48", "title": "Chapter 30"}, {"time": "33057.48", "title": "Author’s Note"}, {"time": "33131.48", "title": "Credits"}]
44	2021-11-11 19:22:25	2021-11-11 19:24:08	/uploads/media/04b98179-2daf-4b5a-9173-182b921d78c5.mpd	39	f	ready	f	/home/chris/src/ambry/uploads/source_media/88cd9c0c-cf42-4718-ab07-a93f122c7753	/uploads/media/04b98179-2daf-4b5a-9173-182b921d78c5.mp4	396.610862	/uploads/media/04b98179-2daf-4b5a-9173-182b921d78c5.m3u8	\N
45	2021-11-11 19:29:18	2021-11-11 19:29:19	/uploads/media/587f3d07-ab66-4148-9e13-3981d8939b01.mpd	5	f	ready	f	/home/chris/src/ambry/uploads/source_media/ba6a92d5-a835-4f9e-9632-6f0df8f6eeab	/uploads/media/587f3d07-ab66-4148-9e13-3981d8939b01.mp4	132.175215	/uploads/media/587f3d07-ab66-4148-9e13-3981d8939b01.m3u8	\N
39	2021-10-27 04:32:27	2021-10-27 04:32:30	/uploads/media/1b060ffa-b306-4ab5-9788-505aa45780c7.mpd	41	f	ready	f	/home/chris/src/ambry/uploads/source_media/34a62540-fb0c-4bba-8fc5-795c18c4b176	/uploads/media/1b060ffa-b306-4ab5-9788-505aa45780c7.mp4	62747.033764	/uploads/media/1b060ffa-b306-4ab5-9788-505aa45780c7.m3u8	\N
43	2021-10-28 04:00:28	2021-11-13 00:08:26	/uploads/media/a9cb42dc-db78-494b-ab61-97e11cdb8018.mpd	49	f	ready	f	/home/chris/src/ambry/uploads/source_media/6744714c-281b-4236-8835-38e0ecaf66da	/uploads/media/a9cb42dc-db78-494b-ab61-97e11cdb8018.mp4	12411.042540	/uploads/media/a9cb42dc-db78-494b-ab61-97e11cdb8018.m3u8	[{"time": "0.00", "title": "01 - Introduction"}, {"time": "692.01", "title": "02 - The Machine"}, {"time": "1218.02", "title": "03 - The Time Traveller Returns"}, {"time": "1980.01", "title": "04 - Time Travelling"}, {"time": "2783.01", "title": "05 - In the Golden Age"}, {"time": "3429.01", "title": "06 - The Sunset of Mankind"}, {"time": "4310.01", "title": "07 - A Sudden Shock"}, {"time": "5191.01", "title": "08 - Explanation"}, {"time": "6758.01", "title": "09 - The Morlocks"}, {"time": "7545.01", "title": "10 - When Night Came"}, {"time": "8500.00", "title": "11 - The Palace of Green Porcelain"}, {"time": "9426.01", "title": "12 - In the Darkness"}, {"time": "10367.01", "title": "13 - The Trap of the White Sphinx"}, {"time": "10801.02", "title": "14 - The Further Vision"}, {"time": "11536.01", "title": "15 - The Time Traveller's Return"}, {"time": "11744.01", "title": "16 - After the Story"}, {"time": "12273.01", "title": "17 - Epilogue"}]
83	2021-11-27 21:42:47	2022-02-14 22:37:43	/uploads/media/0fc1c5ba-d9fd-4a1f-ba97-3d2f67fb1e06.mpd	52	t	ready	t	/home/chris/src/ambry/uploads/source_media/fee6b48d-5449-4b49-ae3d-17809aa81df2	/uploads/media/0fc1c5ba-d9fd-4a1f-ba97-3d2f67fb1e06.mp4	35759.189773	/uploads/media/0fc1c5ba-d9fd-4a1f-ba97-3d2f67fb1e06.m3u8	\N
47	2021-11-12 23:21:06	2021-11-13 07:05:32	/uploads/media/23934e0c-9747-495d-8aff-92f454d06e0f.mpd	17	f	ready	f	/home/chris/src/ambry/uploads/source_media/ea50bfda-0981-48da-b05b-06d3ee877d43	/uploads/media/23934e0c-9747-495d-8aff-92f454d06e0f.mp4	29965.876327	/uploads/media/23934e0c-9747-495d-8aff-92f454d06e0f.m3u8	[{"time": "0.00", "title": "Chapter 01: The Boy Who Lived"}, {"time": "1762.24", "title": "Chapter 02: The Vanishing Glass"}, {"time": "3071.20", "title": "Chapter 03: The Letters From No One"}, {"time": "4529.14", "title": "Chapter 04: The Keeper Of The Keys"}, {"time": "5995.26", "title": "Chapter 05: Diagon Alley"}, {"time": "8633.07", "title": "Chapter 06: The Journey From Platform Nine And Three Quarters"}, {"time": "10930.22", "title": "Chapter 07: The Sorting Hat"}, {"time": "12660.54", "title": "Chapter 08: The Potions Teacher"}, {"time": "13774.94", "title": "Chapter 09: The Midnight Duel"}, {"time": "15635.98", "title": "Chapter 10: Hallowe'en"}, {"time": "17168.84", "title": "Chapter 11: Quidditch"}, {"time": "18445.57", "title": "Chapter 12: The Mirror Of Erised"}, {"time": "20586.38", "title": "Chapter 13: Nicolas Flamel"}, {"time": "21776.04", "title": "Chapter 14: Norbert, The Norwegian Ridgeback"}, {"time": "23054.47", "title": "Chapter 15: The Forbidden Forest"}, {"time": "24998.31", "title": "Chapter 16: Through The Trapdoor"}, {"time": "27475.37", "title": "Chapter 17: The Man With Two Faces"}]
82	2021-11-27 03:06:20	2021-11-27 06:45:18	/uploads/media/54903547-8326-476f-8cf5-fa8443c51b9d.mpd	51	f	ready	f	/home/chris/src/ambry/uploads/source_media/fcbd903c-27a3-4ad7-a6b3-f0a15f666613	/uploads/media/54903547-8326-476f-8cf5-fa8443c51b9d.mp4	47735.095147	/uploads/media/54903547-8326-476f-8cf5-fa8443c51b9d.m3u8	[{"time": "0.00", "title": "Opening Credits"}, {"time": "16.86", "title": "Dedication"}, {"time": "27.59", "title": "Prologue"}, {"time": "760.50", "title": "Part One"}, {"time": "764.18", "title": "1"}, {"time": "1664.87", "title": "2"}, {"time": "2413.20", "title": "3"}, {"time": "2906.95", "title": "4"}, {"time": "3224.09", "title": "5"}, {"time": "4136.17", "title": "6"}, {"time": "4911.90", "title": "7"}, {"time": "6021.26", "title": "8"}, {"time": "6641.00", "title": "Interlude"}, {"time": "7553.72", "title": "Part Two"}, {"time": "7557.57", "title": "9"}, {"time": "8300.01", "title": "10"}, {"time": "9568.89", "title": "11"}, {"time": "10849.38", "title": "12"}, {"time": "11429.88", "title": "13"}, {"time": "12227.53", "title": "14"}, {"time": "13199.47", "title": "Interlude"}, {"time": "14044.12", "title": "Part Three"}, {"time": "14047.99", "title": "15"}, {"time": "14836.66", "title": "16"}, {"time": "15479.25", "title": "17"}, {"time": "15888.94", "title": "18"}, {"time": "17147.14", "title": "19"}, {"time": "18889.93", "title": "20"}, {"time": "20817.70", "title": "21"}, {"time": "22151.68", "title": "22"}, {"time": "23224.96", "title": "23"}, {"time": "24434.44", "title": "24"}, {"time": "25328.22", "title": "25"}, {"time": "26094.71", "title": "26"}, {"time": "26992.11", "title": "Interlude"}, {"time": "27937.58", "title": "Part Four"}, {"time": "27941.41", "title": "27"}, {"time": "28606.97", "title": "28"}, {"time": "29104.43", "title": "29"}, {"time": "30562.36", "title": "30"}, {"time": "31555.53", "title": "31"}, {"time": "32081.74", "title": "32"}, {"time": "33059.25", "title": "33"}, {"time": "34997.56", "title": "34"}, {"time": "35902.81", "title": "35"}, {"time": "36557.20", "title": "36"}, {"time": "37817.76", "title": "Interlude"}, {"time": "37916.82", "title": "Part Five"}, {"time": "37920.73", "title": "37"}, {"time": "39147.05", "title": "38"}, {"time": "39875.70", "title": "39"}, {"time": "41384.25", "title": "40"}, {"time": "42513.67", "title": "41"}, {"time": "43987.21", "title": "42"}, {"time": "46287.51", "title": "43"}, {"time": "46715.50", "title": "Epilogue"}, {"time": "47324.66", "title": "Acknowledgments"}, {"time": "47699.29", "title": "End Credits"}]
\.


--
-- Data for Name: media_narrators; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.media_narrators (id, media_id, narrator_id) FROM stdin;
36	38	11
37	39	10
41	43	11
42	44	4
43	45	4
44	46	17
45	47	18
79	83	2
80	83	4
\.


--
-- Data for Name: narrators; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.narrators (id, inserted_at, updated_at, name, person_id) FROM stdin;
1	2021-09-26 01:40:41	2021-09-26 01:40:41	Ray Porter	6
2	2021-09-26 01:40:41	2021-09-26 01:40:41	Patricia Rodríguez	7
3	2021-09-26 01:40:41	2021-09-26 01:40:41	Wil Wheaton	8
4	2021-09-26 01:40:41	2021-09-26 01:40:41	Amber Benson	9
6	2021-09-26 01:40:41	2021-09-26 01:40:41	David Stifel	11
5	2021-09-26 01:40:41	2021-09-26 19:12:39	Todd McLaren	10
9	2021-09-28 01:42:41	2021-09-28 01:42:41	Jefferson Mays	16
10	2021-10-12 22:07:36	2021-10-12 22:07:36	Mark Bramhall	20
11	2021-10-26 05:12:28	2021-10-26 05:12:28	Cliff Stone	22
17	2021-11-12 07:53:06	2021-11-12 07:53:06	Kate Rudd	32
18	2021-11-12 23:20:28	2021-11-12 23:20:28	Jim Dale	33
\.


--
-- Data for Name: oban_jobs; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.oban_jobs (id, state, queue, worker, args, errors, attempt, max_attempts, inserted_at, scheduled_at, attempted_at, completed_at, attempted_by, discarded_at, priority, tags, meta, cancelled_at) FROM stdin;
\.


--
-- Data for Name: people; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.people (id, inserted_at, updated_at, name, image_path, description) FROM stdin;
1	2021-09-26 01:40:41	2021-09-26 01:40:41	Andy Weir	/uploads/images/Andy-Weir-author-photo-credit-Aubrie-Pick.jpg	Andy Weir built a career as a software engineer until the success of his first published novel, The Martian, allowed him to live out his dream of writing fulltime. He is a lifelong space nerd and a devoted hobbyist of subjects such as relativistic physics, orbital mechanics, and the history of manned spaceflight. He also mixes a mean cocktail. He lives in California.\n
2	2021-09-26 01:40:41	2021-09-26 01:40:41	Becky Chambers	/uploads/images/BC+author+photo.jpg	Becky Chambers is a science fiction author based in Northern California. She is best known for her Hugo Award-winning Wayfarers series, which currently includes The Long Way to a Small, Angry Planet, A Closed and Common Orbit, and Record of a Spaceborn Few. Her books have also been nominated for the Arthur C. Clarke Award, the Locus Award, and the Women's Prize for Fiction, among others. Her most recent work is To Be Taught, If Fortunate, a standalone novella.\n\nBecky has a background in performing arts, and grew up in a family heavily involved in space science. She spends her free time playing video and tabletop games, keeping bees, and looking through her telescope. Having hopped around the world a bit, she’s now back in her home state, where she lives with her wife. She hopes to see Earth from orbit one day.\n
3	2021-09-26 01:40:41	2021-09-26 01:40:41	John Scalzi	/uploads/images/john_scalzi.jpg	John Scalzi writes books, which, considering where you're reading this, makes perfect sense. He's best known for writing science fiction, including the New York Times bestseller "Redshirts," which won the Hugo Award for Best Novel. He also writes non-fiction, on subjects ranging from personal finance to astronomy to film, was the Creative Consultant for the Stargate: Universe television series. He enjoys pie, as should all right thinking people. You can get to his blog by typing the word "Whatever" into Google. No, seriously, try it.\n
4	2021-09-26 01:40:41	2021-09-26 01:40:41	Richard K. Morgan	/uploads/images/richard_k_morgan.jpeg	Richard K. Morgan is the acclaimed author of The Dark Defiles, The Cold Commands, The Steel Remains, Black Man (published in the US as Thirteen), Woken Furies, Market Forces, Broken Angels, and Altered Carbon, a New York Times Notable Book that won the Philip K. Dick Award in 2003.\n\nThe movie rights to Altered Carbon were optioned by Joel Silver and Warner Bros on publication, and the book remained in feature film development until 2015. It is now being turned into a 10 episode Netflix series by Skydance Media. Market Forces, was also optioned to Warner Bros, before it was even published, and it won the John W. Campbell Award in 2005. Black Man won the Arthur C .Clarke Award in 2007 and is currently under movie option to Straight Up films. The Steel Remains won the Gaylactic Spectrum award in 2010, and its sequel, The Cold Commands, was listed in both Kirkus Reviews‘ and NPR’s best Science Fiction / Fantasy books of the Year. The concluding volume, The Dark Defiles, is out now!\n\nRichard is a fluent Spanish speaker and has lived and worked in Madrid, Istanbul, Ankara, London and Glasgow, as well as travelling extensively in the Americas, Africa and Australia. He now lives back in Norfolk in the UK with his Spanish wife Virginia and son Daniel, about five miles away from where he grew up. A bit odd, that, but he’s dealing with it.\n
5	2021-09-26 01:40:41	2021-09-26 01:40:41	Travis Bagwell	/uploads/images/travis_bagwell.jpg	I live in Austin, Texas with my wife and our three dogs. I'm an attorney by day and an avid video game enthusiast by night. Writing fiction had been a secret dream of mine for a while. However, between school and work, that dream seemed impossible to squeeze in. A couple of years ago, I had a bit more time on my hands and I finally decided to put my nerdy interests to work by trying my hand at writing science fiction and fantasy.\n\nI never expected the wildly positive response to my work. I am truly blown away and humbled and I only hope to be able to continue sharing my stories.\n
6	2021-09-26 01:40:41	2021-09-26 01:40:41	Ray Porter	/uploads/images/ray_porter.jpg	Ray Porter has appeared in numerous films and television shows, including Frasier, ER, Will & Grace, The Suite Life of Zack and Cody, and Almost Famous. A fifteen-year veteran of the Oregon Shakespeare Festival, he lives in Los Angeles with his wife and son.\n
7	2021-09-26 01:40:41	2021-09-26 01:40:41	Patricia Rodríguez	/uploads/images/rodriguez.jpg	Patricia Rodriguez is one of the most versatile and accomplished voice actresses in London today, with experience in all genres from audiobooks and commercials to cartoons and video games. Her background in theatre lends a genuine depth and quality to her work.\n
8	2021-09-26 01:40:41	2021-09-26 01:40:41	Wil Wheaton	/uploads/images/wheaton.jpg	Wil Wheaton began acting in commercials at the age of seven, and by the age of ten had appeared in numerous television and film roles. In 1986, his critically acclaimed role in Rob Reiner’s Stand By Me put him in the public spotlight, where he remains to this day. In 1987, Wil was cast as Wesley Crusher in the hit television series Star Trek: The Next Generation. Recently, Wil has held recurring roles on TNT’s Leverage and SyFy’s Eureka; he currently recurs on CBS’s The Big Bang Theory. He played Axis of Anarchy leader Fawkes in Felicia Day’s webseries The Guild, and currently writes, produces, and hosts The Wil Wheaton Project on Syfy. He is also the creator and host of the multiple award-winning webseries Tabletop, which is about to begin its third season..\n\nAs a voice actor, Wil has been featured in video games such as Broken Age, Grand Theft Auto: San Andreas, Brütal Legend, DC Universe Online, Fallout: New Vegas, and Ghost Recon Advanced Warfighter. He has lent his voice talents to animated series including Family Guy, Legion of Superheroes, Ben 10: Alien Force, Generator Rex, Batman: The Brave and the Bold, and Teen Titans.\n\nAs an author, he's published many acclaimed books, among them: Just A Geek, Dancing Barefoot, and The Happiest Days of Our Lives. All of his books grew out of Wil’s immensely popular, award-winning weblog, which he created and maintains at WIL WHEATON dot NET. While most celebrities are happy to let publicists design and maintain their websites, Wil took a decidedly different turn when he started blogging in 2001, when he designed and coded his website on his own.\n\nWil personally maintains a popular social media presence, including a popular Tumblr, Facebook page, and Google Plus page. His frequently-cited Twitter account is followed by over 2.3 million people.\n\nWil is widely recognized as one of the original celebrity bloggers, and is a respected voice in the blogging community. In 2003, Forbes.com readers voted WWdN the “Best Celebrity Weblog.” Wil's blog was chosen by C|Net for inclusion in their 100 most influential blogs, and is an “A” lister, according to Blogebrity.com. In the 2002 weblog awards (the bloggies) Wil won every category in which he was nominated, including “Weblog of the Year.” In 2007, Wil was nominated for a Lifetime Achievement Bloggie, alongside Internet powerhouses Slashdot and Fark. In the 2008 weblog awards, Wil was voted the "Best Celebrity Blogger," and in 2009 Forbes named him the 14th most influential web celebrity. This is all amusing to Wil, who doesn't think of himself as a celebrity, but is instead, "just this guy, you know?"\n
9	2021-09-26 01:40:41	2021-09-26 01:40:41	Amber Benson	/uploads/images/benson.jpg	Amber Benson is what we call "a maker of things." A prolific writer, she is the author of the Calliope Reaper-Jones urban fantasy series—for which she read the audiobooks—and the middle-grade book Among the Ghosts. She has narrated over a half dozen titles, including the John Scalzi bestseller Lock In. Behind the camera, she codirected the Slamdance feature film Drones and cowrote and directed the BBC animated series The Ghosts of Albion. In her previous incarnation as an actor, she spent three years as "Tara Maclay" on the cult television series Buffy the Vampire Slayer. Amber does not own a television.\n
11	2021-09-26 01:40:41	2021-09-26 01:40:41	David Stifel	/uploads/images/stifel.jpg	David Stifel was born and raised in Denver, Colorado. Bitten early by the acting bug, he studied his craft at the Yale School of Drama. After graduation, he found himself in the usual array of interesting day jobs such as casino porter at Lake Tahoe, ESL teacher in Iran, and Egypt, and video game programmer in the Atari/Intellivision era. Concurrently he worked in films and TV shows for such directors as Steven Spielberg (Minority Report), Danny Boyle (A Life Less Ordinary), and Joel Schumacher (The Number 23).\n\nDavid entered the audiobook field in 2011, when he launched a long-term podcast of serializations of the works of Edgar Rice Burroughs. Today he is a multi-award-winning narrator with more than 125 audiobooks to his credit.\n\nHis growing catalog of audiobooks is strong on thrillers, horror, sci-fi, and mysteries. David's rich baritone voice also lends itself very well to nonfiction memoirs and history—popular and academic. His classical acting training makes him very strong with heightened literary language. Pegged as a "character actor" from youth, his facility with numerous characters is frequently praised by reviewers and listeners.\n
12	2021-09-26 01:40:41	2021-09-27 02:30:22	J.K. Rowling	/uploads/images/rowling.jpg	Although she writes under the pen name J.K. Rowling, pronounced like rolling, her name when her first Harry Potter book was published was simply Joanne Rowling. Anticipating that the target audience of young boys might not want to read a book written by a woman, her publishers demanded that she use two initials, rather than her full name. As she had no middle name, she chose K as the second initial of her pen name, from her paternal grandmother Kathleen Ada Bulgen Rowling. She calls herself Jo and has said, "No one ever called me 'Joanne' when I was young, unless they were angry." Following her marriage, she has sometimes used the name Joanne Murray when conducting personal business. During the Leveson Inquiry she gave evidence under the name of Joanne Kathleen Rowling. In a 2012 interview, Rowling noted that she no longer cared that people pronounced her name incorrectly.\n\nRowling was born to Peter James Rowling, a Rolls-Royce aircraft engineer, and Anne Rowling (née Volant), on 31 July 1965 in Yate, Gloucestershire, England, 10 miles (16 km) northeast of Bristol. Her mother Anne was half-French and half-Scottish. Her parents first met on a train departing from King's Cross Station bound for Arbroath in 1964. They married on 14 March 1965. Her mother's maternal grandfather, Dugald Campbell, was born in Lamlash on the Isle of Arran. Her mother's paternal grandfather, Louis Volant, was awarded the Croix de Guerre for exceptional bravery in defending the village of Courcelles-le-Comte during the First World War.\n\nRowling's sister Dianne was born at their home when Rowling was 23 months old. The family moved to the nearby village Winterbourne when Rowling was four. She attended St Michael's Primary School, a school founded by abolitionist William Wilberforce and education reformer Hannah More. Her headmaster at St Michael's, Alfred Dunn, has been suggested as the inspiration for the Harry Potter headmaster Albus Dumbledore.\n\nAs a child, Rowling often wrote fantasy stories, which she would usually then read to her sister. She recalls that: "I can still remember me telling her a story in which she fell down a rabbit hole and was fed strawberries by the rabbit family inside it. Certainly the first story I ever wrote down (when I was five or six) was about a rabbit called Rabbit. He got the measles and was visited by his friends, including a giant bee called Miss Bee." At the age of nine, Rowling moved to Church Cottage in the Gloucestershire village of Tutshill, close to Chepstow, Wales. When she was a young teenager, her great aunt, who Rowling said "taught classics and approved of a thirst for knowledge, even of a questionable kind," gave her a very old copy of Jessica Mitford's autobiography, Hons and Rebels. Mitford became Rowling's heroine, and Rowling subsequently read all of her books.\n\nRowling has said of her teenage years, in an interview with The New Yorker, "I wasn’t particularly happy. I think it’s a dreadful time of life." She had a difficult homelife; her mother was ill and she had a difficult relationship with her father (she is no longer on speaking terms with him). She attended secondary school at Wyedean School and College, where her mother had worked as a technician in the science department. Rowling said of her adolescence, "Hermione [a bookish, know-it-all Harry Potter character] is loosely based on me. She's a caricature of me when I was eleven, which I'm not particularly proud of." Steve Eddy, who taught Rowling English when she first arrived, remembers her as "not exceptional" but "one of a group of girls who were bright, and quite good at English." Sean Harris, her best friend in the Upper Sixth owned a turquoise Ford Anglia, which she says inspired the one in her books.\n
10	2021-09-26 01:40:41	2021-09-26 19:12:39	Todd McLaren	/uploads/images/McLaren_T_D.jpg	Todd McLaren was involved in radio for more than twenty years in cities on both coasts, including Philadelphia, San Francisco, and Los Angeles. He left broadcasting for a full-time career in voice-overs, where he has been heard on more than 5,000 TV and radio commercials, as well as TV promos; narrations for documentaries on such networks as A&E, Discovery, and the History Channel; and films, including Who Framed Roger Rabbit?\n
15	2021-09-28 01:37:24	2021-09-28 01:37:24	James S. A. Corey	/uploads/images/11f59673a71a8b83c4709960258ed5b2.jpg	James S.A. Corey is the pen name of authors Daniel Abraham and Ty Franck.  They both live in Albuquerque, New Mexico. 
16	2021-09-28 01:42:41	2021-09-28 01:42:41	Jefferson Mays	/uploads/images/9c40cacaab6047678aab2af7c9d5c200.jpg	\N
18	2021-10-03 07:50:19	2021-10-03 07:50:19	test	/uploads/images/0e2687e3a6c95084e6ce912aa45d3803.webp	test
21	2021-10-26 05:12:11	2021-10-26 05:12:11	H. G. Wells	/uploads/images/9c6a07d4a398580aa8085ad9d5647649.jpg	\N
22	2021-10-26 05:12:28	2021-10-26 05:12:28	Cliff Stone	/uploads/images/0bd6ef452763c3a6fddc36a385122296.jpg	\N
19	2021-10-12 22:05:50	2021-10-28 20:19:22	Lev Grossman	/uploads/images/0596c7345f79e6d13d8fa55fd4b2ca62.png	\N
20	2021-10-12 22:07:36	2021-11-11 23:36:42	Mark Bramhall	/uploads/images/fa4d0ee3de9e36173885939557f6041a.jpg	\N
31	2021-11-12 07:52:33	2021-11-12 07:52:33	Maureen Johnson	/uploads/images/449834cafa22711604ecb077abdea735.jpg	Maureen Johnson is the #1 New York Times and USA Today bestselling author of several YA novels, including *13 Little Blue Envelopes*, *Suite Scarlett*, *The Name of the Star*, and *Truly Devious*. She has also done collaborative works, such as *Let It Snow* with John Green and Lauren Myracle (now on Netflix), and several works in the Shadowhunter universe with Cassandra Clare. Her work has appeared in publications such as *The New York Times*, Buzzfeed, and *The Guardian*, and she has also served as a scriptwriter for EA Games. She has an MFA in Writing from Columbia University and lives in New York City.
32	2021-11-12 07:53:06	2021-11-12 07:53:06	Kate Rudd	/uploads/images/dd4be6288cc2dcbeefbaeb8623be4150.png	Kate Rudd, winner of 2013 Audie and Odyssey Awards for narration of John Green's The Fault in Our Stars, has been performing audiobooks for nearly a decade. A ten time Audiofile Magazine Earphones Award recipient, Kate’s performances have garnered inclusion in Audiofile’s Best Audiobooks of the Year 2012/2017/2018 and Best Voices of the Year 2012. She has narrated more than 450 titles across a variety of genres. 
33	2021-11-12 23:20:28	2021-11-12 23:20:28	Jim Dale	/uploads/images/9e6b5ed6f06b1f5fd78c812807fdca89.jpg	Jim Dale, MBE (born James Smith, 15 August 1935) is an English actor, voice artist, singer and songwriter. He is best known in the United Kingdom for his many appearances in the Carry On series of films and in the US for narrating the Harry Potter audiobook series, for which he received two Grammy Awards, and the ABC series Pushing Daisies. In the 1970s Dale was a member of Laurence Olivier's National Theatre Company.  \n  \n**Voice work**  \nTo millions of fans in the United States, Jim Dale is the "voice" of Harry Potter. He has recorded all seven books in the Harry Potter series, and as a narrator he has won two Grammy Awards, seven Grammy Nominations and a record ten Audie Awards including "Audio Book of the Year 2004," "Best Children's Narrator 2001/2005/2007/2008," "Best Children's Audio Book 2005," two Benjamin Franklin Awards from the Independent Book Publishers Association (one of these was in 2001 for Harry Potter & the Prisoner of Azkaban)\\[7\\] and twenty three Audio File Earphone Awards. He is also the narrator for the Harry Potter video games, and for many of the interactive "extras" on the Harry Potter DVD releases. He also holds two Guinness World Records: one for having created and recorded 146 different character voices\\[8\\] for one audiobook, Harry Potter and the Deathly Hallows, and one for occupying the first six places in the Top Ten Audio Books of America and Canada 2005.  \n  \nDale also narrated the ABC drama, Pushing Daisies, as "the fairy tale narrator"  \n  \nIn the early 1960s, Dale presented Children's Favourites on BBC Radio, for a year.  \n  \nIn 2003, Queen Elizabeth II honoured Dale with the MBE, for his work in promoting English children's literature.  \n  \nIn December, 2009, for their annual birthday celebration to "The Master", The Noel Coward Society invited Dale as the guest celebrity to lay flowers in front of Coward's statue at New York's Gershwin Theatre, thereby commemorating the 110th birthday of Sir Noel.  \n  \n**Awards for his voice work**  \n2001 Grammy Award - Best Spoken Word Album for Children - Harry Potter and the Goblet of Fire  \n2001 Audie Award - Narrator of the Year - Harry Potter and the Goblet of Fire  \n2004 Audie Award - Audiobook of the year - Harry Potter and the Order of the Phoenix  \n2004 Audie Award - Children's Male Narrator of the Year - Harry Potter and the Order of the Phoenix  \n2005 Audie Award - Classic Narrator - A Christmas Carol  \n2005 Audie Award - Male Narrator of the Year - Peter and the Star Catchers  \n2005 Audie Award - Children's Narrator - Peter and the Starcatchers  \n2007 Audie Award - Male Narrator of the Year - Peter and the Shadow Thieves  \n2008 Audie Award - Solo Narrator - Harry Potter and the Deathly Hallows  \n2008 Grammy Award - Best Spoken Word Album for Children - Harry Potter and the Deathly Hallows  \n2009 Audie Award - Children's male Narrator of the Year - James Herriot's Treasury For Children  \nTwenty three Audiofile Headphone Awards
\.


--
-- Data for Name: player_states; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.player_states (id, inserted_at, updated_at, "position", playback_rate, media_id, user_id, duration, status) FROM stdin;
22	2021-10-27 02:08:04	2021-12-12 00:13:47	23360.828125	1.50	38	1	\N	finished
39	2022-02-13 20:24:58	2022-02-17 00:55:43	5336.949702	1.25	83	1	\N	in_progress
30	2021-11-13 06:50:25	2022-02-20 00:07:01	6834.86199	1.25	46	1	\N	in_progress
23	2021-10-27 04:32:46	2021-12-19 02:23:23	23753.521	1.25	39	1	62747.03515625	in_progress
29	2021-11-11 19:29:30	2021-12-19 02:24:13	88.236	1	45	1	\N	in_progress
31	2021-11-13 06:52:43	2021-12-19 02:42:22	17663.494	1.25	47	1	\N	in_progress
27	2021-11-02 18:51:49	2021-12-07 23:39:10	12403.84	1.25	43	1	\N	finished
28	2021-11-11 19:24:37	2021-11-19 19:14:15	396.61	1	44	1	\N	finished
36	2021-12-07 23:35:17	2021-12-09 02:17:40	0	1	82	1	\N	not_started
\.


--
-- Data for Name: schema_migrations; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.schema_migrations (version, inserted_at) FROM stdin;
20210602181317	2021-09-26 01:40:40
20210602181326	2021-09-26 01:40:40
20210602181335	2021-09-26 01:40:40
20210603014844	2021-09-26 01:40:40
20210603014850	2021-09-26 01:40:40
20210603050937	2021-09-26 01:40:40
20210603055226	2021-09-26 01:40:40
20210610040819	2021-09-26 01:40:40
20210618045525	2021-09-26 01:40:40
20210620003922	2021-09-26 01:40:40
20210620204207	2021-09-26 01:40:40
20210620224553	2021-09-26 01:40:40
20210707215515	2021-09-26 01:40:40
20210801035911	2021-09-26 01:40:40
20210911214811	2021-09-26 01:40:40
20210912011121	2021-09-26 01:40:40
20210912021319	2021-09-26 01:40:40
20210914203806	2021-09-26 01:40:40
20210924225506	2021-09-26 01:40:40
20210928060224	2021-09-28 06:06:55
20210928062348	2021-09-28 06:25:00
20211012193703	2021-10-12 19:38:01
20211020225645	2021-10-20 22:58:11
20211026050428	2021-10-26 05:10:31
20211027214720	2021-10-27 23:23:11
20211028011101	2021-10-28 01:20:43
20211102220725	2021-11-02 22:28:55
20211112041553	2021-11-12 04:28:48
\.


--
-- Data for Name: series; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.series (id, inserted_at, updated_at, name) FROM stdin;
1	2021-09-26 01:40:41	2021-09-26 01:40:41	Takeshi Kovacs
4	2021-09-26 01:40:41	2021-09-26 01:40:41	Lock In
5	2021-09-26 01:40:41	2021-09-26 01:40:41	Wayfarers
6	2021-09-26 01:40:41	2021-09-26 01:40:41	Harry Potter
3	2021-09-26 01:40:41	2021-09-27 23:21:55	Tarot
9	2021-09-28 01:37:38	2021-09-28 01:39:55	The Expanse
2	2021-09-26 01:40:41	2021-10-04 05:54:20	Awaken Online
10	2021-10-12 22:06:59	2021-10-12 22:06:59	The Magicians
7	2021-09-26 01:40:41	2021-10-21 00:50:29	Cormoran Strike
15	2021-11-12 07:54:06	2021-11-12 07:54:06	Truly, Devious
\.


--
-- Data for Name: users; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.users (id, inserted_at, updated_at, email, hashed_password, confirmed_at, admin) FROM stdin;
1	2021-09-26 01:44:47	2022-02-18 21:40:37	chris@xn--dos-dma.com	$argon2id$v=19$m=131072,t=8,p=4$14/ugtJ4WWbs8RSZLbiF6Q$yv3ji0+22GgyKgqhfsg5D8MksQ6vm9fiY2Tm12Ts8pA	2022-02-18 21:40:37	t
\.


--
-- Data for Name: users_tokens; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.users_tokens (id, inserted_at, user_id, token, context, sent_to) FROM stdin;
37	2021-10-11 22:48:02	1	\\x71ae7c348c7345935d8d8077e42f4fe54bf3a66d96b98349758eeeda92c4e77e	session	\N
38	2021-10-12 04:54:09	1	\\x327267a270cf88a3617a799af4869514f2afb472a2e7b51f41d0a0cb1be8d6f4	session	\N
39	2021-10-13 17:41:42	1	\\xa128280d9ae6bc5150448724b65669a4e95553a368cb2ed69e8eb9f3f3e5314e	session	\N
40	2021-10-13 22:53:15	1	\\x5595e0124681112179f80001ff7ed3af24dc8c687302f1eb6d0949731cada335	session	\N
41	2021-10-21 01:46:25	1	\\xc106224ac49025cf8aa02bd0435915c4508fa2d9f2c781ca183fd59779ed1293	session	\N
42	2021-10-21 05:07:24	1	\\xe367bafe59c7f12d0177e754b6a032e13a5d25b0895b94c76df189fa16dde800	session	\N
43	2021-10-21 19:25:10	1	\\xc40eec5699b28703671132d3dd7a625746672c2a48802ae0ea036a5d618deb49	session	\N
44	2021-10-21 19:28:58	1	\\x4dfa20856372af6b4e57caabac02b1b02f563d8f290736632ea9de613f06e23b	session	\N
45	2021-10-27 03:16:32	1	\\x19ac4335c8c4e416eff14cf60c6a2230a7cd3fa165c37503f3e341cbf21ac3f0	session	\N
46	2021-10-27 04:01:02	1	\\xfb849b66439b36264bb52deb9337de5638160df73b45d8871c2ce4a842afab49	session	\N
47	2021-10-27 04:57:40	1	\\x22f18ba32a2920506e09ddb3a71ebd35c2e14ad0dfffc9168987cfde9e3346b9	session	\N
48	2021-10-28 07:42:46	1	\\xf39e13d38a2b854f5d774033fad25de9604f63423bfa620a2a65b4cf6aefbe09	session	\N
49	2021-10-31 22:42:10	1	\\xd6a0387120075c4429e31426c66e4b136a92d431b03b694608ef97c97cf6acd4	session	\N
50	2021-11-01 05:23:12	1	\\x34ae6732999de07e43a5de157e1b84a1c19113e5c65803b2ae22ec06c5361bcb	session	\N
51	2021-11-03 22:34:42	1	\\x2fa024362a607b800e4dec9315ba89cd80777c19defb6348e0657e1bc5b58716	session	\N
52	2021-11-04 02:55:15	1	\\x133ed87c13e836c0cf50f9d7dc8ca50c46fbd1a7edbb8bd1ad03c56c461aa089	session	\N
53	2021-11-05 01:11:12	1	\\xd7d7515a01318e7dae306d64f68252e8b724a679699cfcd377509c8a6b0ef1cd	session	\N
54	2021-11-05 20:31:35	1	\\x08813d7ab3278d84e3406ba1bad02e9039b95c0dd8d6c67d3dbbc71369906972	session	\N
55	2021-11-19 19:25:04	1	\\x974ee0a6fb4cc4e129c0dfaa73c41093babba37017ee774721b13d5a74db43e4	session	\N
56	2021-11-23 21:17:24	1	\\x6ef3452f15b6bfe536aed9f590166b8298e45683d714156b66866a884b83750f	session	\N
57	2021-11-24 02:56:44	1	\\xd4d2c2a98bfe43c997db7cd7bcc1ca8838190e50fd080dac10fedcd1423e6bf3	session	\N
58	2021-12-02 22:25:08	1	\\xff460e5fd5a1ce48f2f946fc01ce01794e992259607efd8cb4b24be624ebaaea	session	\N
59	2021-12-06 22:57:08	1	\\x60a54da1c3f9ea4872776cf22be99d9c22a2b3abded79f351ac44761015f6686	session	\N
60	2021-12-07 19:46:48	1	\\xfc2f137ce4155011464c7ca07d2def023200e5a48e13d6fab2f78636fac2dc9c	session	\N
61	2021-12-08 20:58:34	1	\\xb6d4a5c195c2272546cb20086e462d77a345f7fe11fa45122d7d598b27d382d5	session	\N
62	2021-12-08 21:00:03	1	\\xd06dd62950f059f8cc51aefc8b5213f8c00f42b722206b5ddd1f5780ccdd7200	session	\N
63	2021-12-08 21:00:51	1	\\x0c858908426c520eecd5d10c730242d6fb51fd6f7eeb27f50cea7405d1ee190a	session	\N
64	2021-12-08 21:20:40	1	\\x6b4ce9f1a28fc0ac19bbc38ae44fd87cc9c54ebf0e9fa4741ec0911572936466	session	\N
65	2021-12-08 21:41:34	1	\\x89129b9b521458fb0065d46e5e71b24b068cc5efbbd7774f2424ac02b4c817c9	session	\N
66	2021-12-09 01:46:46	1	\\xd33271065c0d8e52594b1c3954aa500cd690d745769379a26a86c006a9c089e7	session	\N
67	2021-12-09 02:07:12	1	\\x80b367cf97cd2341bf3a724618a6f3192b7a22c9ed7ba86f539ffb005972158e	session	\N
68	2021-12-09 02:21:44	1	\\x2f88532ed057a24d5561302b71287fd2e8bc1856df81afcde536e5a9294695fc	session	\N
69	2021-12-09 02:29:53	1	\\x15914d286d960759d9724adeee5929551227f371aa7f0128d05522549246527b	session	\N
70	2021-12-10 20:35:51	1	\\x82c4093bfe6d532fe9db95a39d3b91401ec351e7f474bff5fbc1c77b6f58b402	session	\N
71	2021-12-14 00:01:52	1	\\x478d6b00285bafdee3c85b42882356a4666078c0e5a647631e14603b2906708e	session	\N
72	2021-12-14 00:46:12	1	\\xd26a4db4ac22658d9117ca8c1e328d0657a87bd8a7687cfced2019e3299e5ecc	session	\N
73	2021-12-19 01:58:10	1	\\x6d5917afeae663b4c91b758f86d02fa974652472f7615a7c4589860234fb633a	session	\N
74	2021-12-22 20:02:59	1	\\x29bf061b337225f0e6df1eb95503d924596ecc6c4fd7866a28f962f7a9a31665	session	\N
75	2021-12-22 20:09:31	1	\\xd5f1ff9ccefea4c61ab6aa08c5bf9a9fd1b3bd19a10648bd66549e88aaa44fa5	session	\N
76	2021-12-22 22:50:35	1	\\x6849eca7157a9c6355267e4cac1c6ca5943120bfa81409f694898f2478c53aab	session	\N
77	2021-12-22 23:37:50	1	\\xa2700bd8743f6b4ddb955f478b3b0debb744a34f9814bec4d15563409b6d4e7e	session	\N
81	2022-02-18 21:19:10	1	\\x27a508035e66f48e7b1fccb336fbef007e25f21f865cdf3c89e1d70ffebb2491	reset_password	chris@xn--dos-dma.com
87	2022-02-19 05:27:51	1	\\x92f5e357aa9c02983c16626c67235de48185df5421ecdb0c0c8da3a51acd1ac5	session	\N
88	2022-02-20 20:59:44	1	\\xa58d4e735512ea50aea2cd228f52d922eb51a6f9db36b66e9f95ac4a21d11021	session	\N
90	2022-02-24 04:04:39	1	\\xf5f2f0efe87163871421471d017ce452701ff913a796c9eaa41e1d91f72def38	session	\N
\.


--
-- Name: authors_books_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.authors_books_id_seq', 47, true);


--
-- Name: authors_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.authors_id_seq', 22, true);


--
-- Name: bookmarks_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.bookmarks_id_seq', 41, true);


--
-- Name: books_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.books_id_seq', 52, true);


--
-- Name: books_series_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.books_series_id_seq', 57, true);


--
-- Name: media_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.media_id_seq', 83, true);


--
-- Name: media_narrators_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.media_narrators_id_seq', 80, true);


--
-- Name: narrators_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.narrators_id_seq', 18, true);


--
-- Name: oban_jobs_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.oban_jobs_id_seq', 46, true);


--
-- Name: people_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.people_id_seq', 33, true);


--
-- Name: player_states_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.player_states_id_seq', 39, true);


--
-- Name: series_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.series_id_seq', 15, true);


--
-- Name: users_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.users_id_seq', 1, true);


--
-- Name: users_tokens_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.users_tokens_id_seq', 90, true);


--
-- Name: authors_books authors_books_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.authors_books
    ADD CONSTRAINT authors_books_pkey PRIMARY KEY (id);


--
-- Name: authors authors_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.authors
    ADD CONSTRAINT authors_pkey PRIMARY KEY (id);


--
-- Name: bookmarks bookmarks_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.bookmarks
    ADD CONSTRAINT bookmarks_pkey PRIMARY KEY (id);


--
-- Name: books books_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.books
    ADD CONSTRAINT books_pkey PRIMARY KEY (id);


--
-- Name: books_series books_series_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.books_series
    ADD CONSTRAINT books_series_pkey PRIMARY KEY (id);


--
-- Name: media_narrators media_narrators_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.media_narrators
    ADD CONSTRAINT media_narrators_pkey PRIMARY KEY (id);


--
-- Name: media media_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.media
    ADD CONSTRAINT media_pkey PRIMARY KEY (id);


--
-- Name: narrators narrators_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.narrators
    ADD CONSTRAINT narrators_pkey PRIMARY KEY (id);


--
-- Name: oban_jobs oban_jobs_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.oban_jobs
    ADD CONSTRAINT oban_jobs_pkey PRIMARY KEY (id);


--
-- Name: people people_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.people
    ADD CONSTRAINT people_pkey PRIMARY KEY (id);


--
-- Name: player_states player_states_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.player_states
    ADD CONSTRAINT player_states_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: series series_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.series
    ADD CONSTRAINT series_pkey PRIMARY KEY (id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: users_tokens users_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users_tokens
    ADD CONSTRAINT users_tokens_pkey PRIMARY KEY (id);


--
-- Name: authors_books_author_id_book_id_index; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX authors_books_author_id_book_id_index ON public.authors_books USING btree (author_id, book_id);


--
-- Name: books_series_book_id_series_id_index; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX books_series_book_id_series_id_index ON public.books_series USING btree (book_id, series_id);


--
-- Name: media_narrators_media_id_narrator_id_index; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX media_narrators_media_id_narrator_id_index ON public.media_narrators USING btree (media_id, narrator_id);


--
-- Name: oban_jobs_args_index; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX oban_jobs_args_index ON public.oban_jobs USING gin (args);


--
-- Name: oban_jobs_meta_index; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX oban_jobs_meta_index ON public.oban_jobs USING gin (meta);


--
-- Name: oban_jobs_queue_state_priority_scheduled_at_id_index; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX oban_jobs_queue_state_priority_scheduled_at_id_index ON public.oban_jobs USING btree (queue, state, priority, scheduled_at, id);


--
-- Name: player_states_media_id_index; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX player_states_media_id_index ON public.player_states USING btree (media_id);


--
-- Name: player_states_user_id_index; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX player_states_user_id_index ON public.player_states USING btree (user_id);


--
-- Name: users_email_index; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX users_email_index ON public.users USING btree (email);


--
-- Name: users_tokens_context_token_index; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX users_tokens_context_token_index ON public.users_tokens USING btree (context, token);


--
-- Name: users_tokens_user_id_index; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX users_tokens_user_id_index ON public.users_tokens USING btree (user_id);


--
-- Name: oban_jobs oban_notify; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER oban_notify AFTER INSERT ON public.oban_jobs FOR EACH ROW EXECUTE FUNCTION public.oban_jobs_notify();


--
-- Name: authors_books authors_books_author_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.authors_books
    ADD CONSTRAINT authors_books_author_id_fkey FOREIGN KEY (author_id) REFERENCES public.authors(id);


--
-- Name: authors_books authors_books_book_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.authors_books
    ADD CONSTRAINT authors_books_book_id_fkey FOREIGN KEY (book_id) REFERENCES public.books(id) ON DELETE CASCADE;


--
-- Name: authors authors_person_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.authors
    ADD CONSTRAINT authors_person_id_fkey FOREIGN KEY (person_id) REFERENCES public.people(id) ON DELETE CASCADE;


--
-- Name: bookmarks bookmarks_media_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.bookmarks
    ADD CONSTRAINT bookmarks_media_id_fkey FOREIGN KEY (media_id) REFERENCES public.media(id) ON DELETE CASCADE;


--
-- Name: bookmarks bookmarks_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.bookmarks
    ADD CONSTRAINT bookmarks_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: books_series books_series_book_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.books_series
    ADD CONSTRAINT books_series_book_id_fkey FOREIGN KEY (book_id) REFERENCES public.books(id) ON DELETE CASCADE;


--
-- Name: books_series books_series_series_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.books_series
    ADD CONSTRAINT books_series_series_id_fkey FOREIGN KEY (series_id) REFERENCES public.series(id) ON DELETE CASCADE;


--
-- Name: media media_book_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.media
    ADD CONSTRAINT media_book_id_fkey FOREIGN KEY (book_id) REFERENCES public.books(id);


--
-- Name: media_narrators media_narrators_media_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.media_narrators
    ADD CONSTRAINT media_narrators_media_id_fkey FOREIGN KEY (media_id) REFERENCES public.media(id) ON DELETE CASCADE;


--
-- Name: media_narrators media_narrators_narrator_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.media_narrators
    ADD CONSTRAINT media_narrators_narrator_id_fkey FOREIGN KEY (narrator_id) REFERENCES public.narrators(id);


--
-- Name: narrators narrators_person_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.narrators
    ADD CONSTRAINT narrators_person_id_fkey FOREIGN KEY (person_id) REFERENCES public.people(id) ON DELETE CASCADE;


--
-- Name: player_states player_states_media_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.player_states
    ADD CONSTRAINT player_states_media_id_fkey FOREIGN KEY (media_id) REFERENCES public.media(id) ON DELETE CASCADE;


--
-- Name: player_states player_states_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.player_states
    ADD CONSTRAINT player_states_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: users_tokens users_tokens_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users_tokens
    ADD CONSTRAINT users_tokens_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

