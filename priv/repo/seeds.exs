# Script for populating the database with some example books and media. You can
# run it with:
#
#     mix ecto.seed

alias Ambry.Books.Book
alias Ambry.Media.Media
alias Ambry.Media.MediaNarrator
alias Ambry.People.Author
alias Ambry.People.BookAuthor
alias Ambry.People.Narrator
alias Ambry.People.Person
alias Ambry.Repo

cwd = File.cwd!()

Repo.transaction(fn ->
  %Person{authors: [asimov]} =
    Repo.insert!(%Person{
      name: "Isaac Asimov",
      image_path: "/uploads/images/9a33009cdd95c97e42faf0538685a634.jpg",
      description: """
      Isaac Asimov was a Russian-born, American author, a professor of biochemistry, and a highly successful writer, best known for his works of science fiction and for his popular science books.

      Professor Asimov is generally considered one of the most prolific writers of all time, having written or edited more than 500 books and an estimated 90,000 letters and postcards. He has works published in nine of the ten major categories of the Dewey Decimal System (lacking only an entry in the 100s category of Philosophy).

      Asimov is widely considered a master of the science-fiction genre and, along with Robert A. Heinlein and Arthur C. Clarke, was considered one of the "Big Three" science-fiction writers during his lifetime. Asimov's most famous work is the Foundation Series; his other major series are the Galactic Empire series and the Robot series, both of which he later tied into the same fictional universe as the Foundation Series to create a unified "future history" for his stories much like those pioneered by Robert A. Heinlein and previously produced by Cordwainer Smith and Poul Anderson. He penned numerous short stories, among them "Nightfall", which in 1964 was voted by the Science Fiction Writers of America the best short science fiction story of all time, a title many still honor. He also wrote mysteries and fantasy, as well as a great amount of nonfiction. Asimov wrote the Lucky Starr series of juvenile science-fiction novels using the pen name Paul French.

      Most of Asimov's popularized science books explain scientific concepts in a historical way, going as far back as possible to a time when the science in question was at its simplest stage. He often provides nationalities, birth dates, and death dates for the scientists he mentions, as well as etymologies and pronunciation guides for technical terms. Examples include his Guide to Science, the three volume set Understanding Physics, and Asimov's Chronology of Science and Discovery.

      Asimov was a long-time member and Vice President of Mensa International, albeit reluctantly; he described some members of that organization as "brain-proud and aggressive about their IQs" He took more joy in being president of the American Humanist Association. The asteroid 5020 Asimov, the magazine Asimov's Science Fiction, a Brooklyn, NY elementary school, and two different Isaac Asimov Awards are named in his honor.
      """,
      authors: [
        %Author{
          name: "Isaac Asimov"
        }
      ]
    })

  %Person{authors: [dick]} =
    Repo.insert!(%Person{
      name: "Philip K. Dick",
      image_path: "/uploads/images/c3357e5e449ca624a999e41b622cd161.jpg",
      description: """
      Philip K. Dick was born in Chicago in 1928 and lived most of his life in California. In 1952, he began writing professionally and proceeded to write numerous novels and short-story collections. He won the Hugo Award for the best novel in 1962 for _The Man in the High Castle_ and the John W. Campbell Memorial Award for best novel of the year in 1974 for _Flow My Tears, the Policeman Said_. Philip K. Dick died on March 2, 1982, in Santa Ana, California, of heart failure following a stroke.

      In addition to 44 published novels, Dick wrote approximately 121 short stories, most of which appeared in science fiction magazines during his lifetime. Although Dick spent most of his career as a writer in near-poverty, ten of his stories have been adapted into popular films since his death, including _Blade Runner, Total Recall, A Scanner Darkly, Minority Report, Paycheck, Next, Screamers_, and _The Adjustment Bureau_. In 2005, Time magazine named _Ubik_ one of the one hundred greatest English-language novels published since 1923. In 2007, Dick became the first science fiction writer to be included in The Library of America series.
      """,
      authors: [
        %Author{
          name: "Philip K. Dick"
        }
      ]
    })

  %Person{narrators: [grothmann]} =
    Repo.insert!(%Person{
      name: "Dale Grothmann",
      image_path: "/uploads/images/2ce59067096c57b5f248abe440a467f1.png",
      description: """
      A LibriVox narrator
      """,
      narrators: [
        %Narrator{
          name: "Dale Grothmann"
        }
      ]
    })

  %Person{narrators: [gurzynski]} =
    Repo.insert!(%Person{
      name: "Dan Gurzynski",
      image_path: "/uploads/images/2ce59067096c57b5f248abe440a467f1.png",
      description: """
      A LibriVox narrator
      """,
      narrators: [
        %Narrator{
          name: "Dan Gurzynski"
        }
      ]
    })

  %Person{narrators: [margarite]} =
    Repo.insert!(%Person{
      name: "Gregg Margarite",
      image_path: "/uploads/images/2ce59067096c57b5f248abe440a467f1.png",
      description: """
      A LibriVox narrator
      """,
      narrators: [
        %Narrator{
          name: "Gregg Margarite"
        }
      ]
    })

  the_hanging_stranger =
    Repo.insert!(%Book{
      title: "The Hanging Stranger",
      published: ~D[1953-12-01],
      book_authors: [
        %BookAuthor{author_id: dick.id}
      ]
    })

  lets_get_together =
    Repo.insert!(%Book{
      title: "Let's Get Together",
      published: ~D[1957-02-01],
      book_authors: [
        %BookAuthor{author_id: asimov.id}
      ]
    })

  the_eyes_have_it =
    Repo.insert!(%Book{
      title: "The Eyes Have It",
      published: ~D[1953-06-01],
      book_authors: [
        %BookAuthor{author_id: dick.id}
      ]
    })

  youth =
    Repo.insert!(%Book{
      title: "Youth",
      published: ~D[1952-05-06],
      book_authors: [
        %BookAuthor{author_id: asimov.id}
      ]
    })

  Repo.insert!(%Media{
    book_id: the_hanging_stranger.id,
    image_path: "/uploads/images/39e43aece0d313944f4d6cfa83367a70.jpg",
    description: """
    'The Hanging Stranger' is a short story about a man who finds a dead stranger hanging from a lamp post and begins to realize that his town is not what he thought it was.
    """,
    source_path: Path.join(cwd, "uploads/source_media/7ba49ac7-bf3f-4292-aa5c-3b5ac8c13553"),
    mpd_path: "/uploads/media/4bbb08a5-e668-4b95-81b3-ec2148bfe359.mpd",
    mp4_path: "/uploads/media/4bbb08a5-e668-4b95-81b3-ec2148bfe359.mp4",
    hls_path: "/uploads/media/4bbb08a5-e668-4b95-81b3-ec2148bfe359.m3u8",
    full_cast: false,
    abridged: false,
    status: :ready,
    duration: Decimal.new("2562.194286"),
    media_narrators: [
      %MediaNarrator{
        narrator_id: grothmann.id
      }
    ]
  })

  Repo.insert!(%Media{
    book_id: lets_get_together.id,
    image_path: "/uploads/images/2656d63152439460a48f2843beb3acaf.jpg",
    description: """
    "Let's Get Together" is a science fiction short story by American writer Isaac Asimov. It was originally published in the February 1957 issue of Infinity Science Fiction, and included in the collections The Rest of the Robots (1964) and The Complete Robot (1982). The robots in this tale are very different from Asimov's norm, being quite happy to work as war machines. The tale is also based on a continuation of Cold War hostility, rather than the peaceful unified world of most of the robot stories.
    """,
    source_path: Path.join(cwd, "uploads/source_media/eb861262-e11d-4bc3-8741-3a386a0ba444"),
    mpd_path: "/uploads/media/112de3cd-e3d2-43d8-be8c-20d0dd0751cf.mpd",
    mp4_path: "/uploads/media/112de3cd-e3d2-43d8-be8c-20d0dd0751cf.mp4",
    hls_path: "/uploads/media/112de3cd-e3d2-43d8-be8c-20d0dd0751cf.m3u8",
    full_cast: false,
    abridged: false,
    status: :ready,
    duration: Decimal.new("2347.569524"),
    media_narrators: [
      %MediaNarrator{
        narrator_id: gurzynski.id
      }
    ]
  })

  Repo.insert!(%Media{
    book_id: the_eyes_have_it.id,
    image_path: "/uploads/images/31da0b1fd1ea0cc4b70e885ff2a73e53.jpg",
    description: """
    **_"It was quite by accident I discovered this incredible invasion of Earth by lifeforms from another planet. As yet, I haven't done anything about it; I can't think of anything to do."_**

    Nobody blends satire and science fiction like renowned luminary of the genre Philip K. Dick. This short but utterly memorable tale tells the story of a man who is utterly convinced that the world is being overrun by aliens. Is he correct, or wildly off-base? Read _The Eyes Have It_ to find out.
    """,
    source_path: Path.join(cwd, "uploads/source_media/3605fcfb-7b6e-46c5-959d-44e6e41631fc"),
    mpd_path: "/uploads/media/c365498e-20d5-491a-befe-85f900eddd5a.mpd",
    mp4_path: "/uploads/media/c365498e-20d5-491a-befe-85f900eddd5a.mp4",
    hls_path: "/uploads/media/c365498e-20d5-491a-befe-85f900eddd5a.m3u8",
    full_cast: false,
    abridged: false,
    status: :ready,
    duration: Decimal.new("451.735510"),
    media_narrators: [
      %MediaNarrator{
        narrator_id: margarite.id
      }
    ]
  })

  Repo.insert!(%Media{
    book_id: youth.id,
    image_path: "/uploads/images/810e068bbf78088cbf7f00a5e13a8e6a.jpg",
    description: """
    Two young boys find some very unusual new pets in this short story from a Grand Master of Science Fiction.

    Tagging along while his astronomer father visits an industrialist at his vast estate, young Slim is lucky enough to make fast friends with the industrialist’s son, Red, who has recently caught some very strange animals on the property.

    The animals seem intelligent enough, and Red recruits Slim to help him train the odd creatures to do circus tricks. But the boys are about to discover their playthings aren’t exactly animals—and they’ve allowed themselves to be caught for a reason . . .

    Youth is a riveting tale from the author of countless classics, including I, Robot and the Foundation Trilogy, which won the Hugo Award for Best All-Time Series.
    """,
    source_path: Path.join(cwd, "uploads/source_media/ab963d4f-029e-4ca5-817a-1854bed2a600"),
    mpd_path: "/uploads/media/57031423-3891-40df-82a3-af99a97de567.mpd",
    mp4_path: "/uploads/media/57031423-3891-40df-82a3-af99a97de567.mp4",
    hls_path: "/uploads/media/57031423-3891-40df-82a3-af99a97de567.m3u8",
    full_cast: false,
    abridged: false,
    status: :ready,
    duration: Decimal.new("3973.485714"),
    media_narrators: [
      %MediaNarrator{
        narrator_id: margarite.id
      }
    ]
  })
end)
