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
alias Ambry.Thumbnails

# dump people
# Ambry.People.Person |> Ambry.Repo.all() |> Ambry.Repo.preload([:authors, :narrators]) |> IO.inspect(limit: :infinity); nil

# dump books
# Ambry.Books.Book |> Ambry.Repo.all() |> Ambry.Repo.preload(:book_authors) |> IO.inspect(limit: :infinity); nil

# dump media
# Ambry.Media.Media |> Ambry.Repo.all() |> Ambry.Repo.preload(:media_narrators) |> IO.inspect(limit: :infinity); nil

cwd = File.cwd!()

Repo.transaction(fn ->
  ## People ##

  %{authors: [jules_verne]} =
    Repo.insert!(%Person{
      authors: [
        %Author{
          name: "Jules Verne"
        }
      ],
      thumbnails: %Thumbnails{
        extra_small: "/uploads/images/001a07ae-2bf5-484c-b7c2-c0b62084651d-xs.webp",
        small: "/uploads/images/001a07ae-2bf5-484c-b7c2-c0b62084651d-sm.webp",
        medium: "/uploads/images/001a07ae-2bf5-484c-b7c2-c0b62084651d-md.webp",
        large: "/uploads/images/001a07ae-2bf5-484c-b7c2-c0b62084651d-md.webp",
        extra_large: "/uploads/images/001a07ae-2bf5-484c-b7c2-c0b62084651d-md.webp",
        thumbhash: "01kGBQB3h4CHd4eIeHiIeHhwhgdH",
        blurhash: "LNExFKRk0Mxa~ANHE2xZENj[xFWV"
      },
      name: "Jules Verne",
      description:
        "Jules Verne (1828-1905) was a French author best known for his tales of adventure, including Twenty Thousand Leagues under the Sea, Journey to the Center of the Earth, and Around the World in Eighty Days. A true visionary, Verne foresaw the skyscraper, the submarine, and the airplane, among many other inventions, and is now regarded as one of the fathers of science fiction.",
      image_path: "/uploads/images/001a07ae-2bf5-484c-b7c2-c0b62084651d.jpg"
    })

  %{authors: [h_g_wells]} =
    Repo.insert!(%Person{
      authors: [
        %Author{
          name: "H.G. Wells"
        }
      ],
      thumbnails: %Thumbnails{
        extra_small: "/uploads/images/464c6305-f307-4504-8cdb-54ee523eb8c2-xs.webp",
        small: "/uploads/images/464c6305-f307-4504-8cdb-54ee523eb8c2-sm.webp",
        medium: "/uploads/images/464c6305-f307-4504-8cdb-54ee523eb8c2-md.webp",
        large: "/uploads/images/464c6305-f307-4504-8cdb-54ee523eb8c2-lg.webp",
        extra_large: "/uploads/images/464c6305-f307-4504-8cdb-54ee523eb8c2-xl.webp",
        thumbhash: "4ZoABQBnh3N5B2h3iHSXiJiMfzYH",
        blurhash: nil
      },
      name: "H.G. Wells",
      description:
        "The son of a professional cricketer and a lady's maid, H. G. Wells (1866-1946) served apprenticeships as a draper and a chemist's assistant before winning a scholarship to the prestigious Normal School of Science in London. While he is best remembered for his groundbreaking science fiction novels, including The Time Machine, The War of the Worlds, The Invisible Man, and The Island of Doctor Moreau, Wells also wrote extensively on politics and social matters and was one of the foremost public intellectuals of his day.",
      image_path: "/uploads/images/464c6305-f307-4504-8cdb-54ee523eb8c2.jpg"
    })

  %{authors: [l_m_montgomery]} =
    Repo.insert!(%Person{
      authors: [
        %Author{
          name: "L.M. Montgomery"
        }
      ],
      thumbnails: %Thumbnails{
        extra_small: "/uploads/images/6330a96e-564a-4d43-b067-4594e0cb1620-xs.webp",
        small: "/uploads/images/6330a96e-564a-4d43-b067-4594e0cb1620-sm.webp",
        medium: "/uploads/images/6330a96e-564a-4d43-b067-4594e0cb1620-md.webp",
        large: "/uploads/images/6330a96e-564a-4d43-b067-4594e0cb1620-md.webp",
        extra_large: "/uploads/images/6330a96e-564a-4d43-b067-4594e0cb1620-md.webp",
        thumbhash: "bDgCBQCYeG+Fl4mYSNh7gneAdgZp",
        blurhash: "LHM6#e_N%Nae-=t7j[M{IAM_%Mx]"
      },
      name: "L.M. Montgomery",
      description:
        "Lucy Maud Montgomery was a Canadian author, best known for a series of novels beginning with Anne of Green Gables, published in 1908.\n\nMontgomery was born at Clifton, Prince Edward Island, Nov. 30, 1874. She came to live at Leaskdale, north of Uxbridge Ontario, after her wedding with Rev. Ewen Macdonald on July 11, 1911. She had three children and wrote close to a dozen books while she was living in the Leaskdale Manse before the family moved to Norval, Ontario in 1926. She died in Toronto April 24, 1942 and was buried at Cavendish, Prince Edward Island.",
      image_path: "/uploads/images/6330a96e-564a-4d43-b067-4594e0cb1620.jpg"
    })

  %{authors: [arthur_conan_doyle]} =
    Repo.insert!(%Person{
      authors: [
        %Author{
          name: "Arthur Conan Doyle"
        }
      ],
      thumbnails: %Thumbnails{
        extra_small: "/uploads/images/d4a1addc-e65b-4f90-8282-0fdc2e275d9f-xs.webp",
        small: "/uploads/images/d4a1addc-e65b-4f90-8282-0fdc2e275d9f-sm.webp",
        medium: "/uploads/images/d4a1addc-e65b-4f90-8282-0fdc2e275d9f-md.webp",
        large: "/uploads/images/d4a1addc-e65b-4f90-8282-0fdc2e275d9f-lg.webp",
        extra_large: "/uploads/images/d4a1addc-e65b-4f90-8282-0fdc2e275d9f-xl.webp",
        thumbhash: "tBgCBQC2iHJ4ueeYj3yit5Z/aPiH",
        blurhash: "LpGIcSt6WB%L~pxuWBt6-:%2j[R*"
      },
      name: "Arthur Conan Doyle",
      description:
        "Sir Arthur Ignatius Conan Doyle was a British writer and physician. He created the character Sherlock Holmes in 1887 for A Study in Scarlet, the first of four novels and fifty-six short stories about Holmes and Dr. Watson. The Sherlock Holmes stories are milestones in the field of crime fiction.\nDoyle was a prolific writer. In addition to the Holmes stories, his works include fantasy and science fiction stories about Professor Challenger, and humorous stories about the Napoleonic soldier Brigadier Gerard, as well as plays, romances, poetry, non-fiction, and historical novels. One of Doyle's early short stories, \"J. Habakuk Jephson's Statement\" (1884), helped to popularise the mystery of the brigantine Mary Celeste, found drifting at sea with no crew member aboard.",
      image_path: "/uploads/images/d4a1addc-e65b-4f90-8282-0fdc2e275d9f.jpg"
    })

  %{authors: [edgar_rice_burroughs]} =
    Repo.insert!(%Person{
      authors: [
        %Author{
          name: "Edgar Rice Burroughs"
        }
      ],
      thumbnails: %Thumbnails{
        extra_small: "/uploads/images/64e3c1dd-0c25-4889-98e9-f5756a279f04-xs.webp",
        small: "/uploads/images/64e3c1dd-0c25-4889-98e9-f5756a279f04-sm.webp",
        medium: "/uploads/images/64e3c1dd-0c25-4889-98e9-f5756a279f04-md.webp",
        large: "/uploads/images/64e3c1dd-0c25-4889-98e9-f5756a279f04-md.webp",
        extra_large: "/uploads/images/64e3c1dd-0c25-4889-98e9-f5756a279f04-md.webp",
        thumbhash: "cEkBBQKFda+nCIaWeHk4Z3tQb/gK",
        blurhash: nil
      },
      name: "Edgar Rice Burroughs",
      description:
        "Edgar Rice Burroughs was an American author, best known for his creation of the jungle hero Tarzan and the heroic John Carter, although he produced works in many genres.",
      image_path: "/uploads/images/64e3c1dd-0c25-4889-98e9-f5756a279f04.jpg"
    })

  %{authors: [rudyard_kipling]} =
    Repo.insert!(%Person{
      authors: [
        %Author{
          name: "Rudyard Kipling"
        }
      ],
      thumbnails: %Thumbnails{
        extra_small: "/uploads/images/26c057fe-e508-48f9-9c1c-f0f1809465ae-xs.webp",
        small: "/uploads/images/26c057fe-e508-48f9-9c1c-f0f1809465ae-sm.webp",
        medium: "/uploads/images/26c057fe-e508-48f9-9c1c-f0f1809465ae-md.webp",
        large: "/uploads/images/26c057fe-e508-48f9-9c1c-f0f1809465ae-lg.webp",
        extra_large: "/uploads/images/26c057fe-e508-48f9-9c1c-f0f1809465ae-xl.webp",
        thumbhash: "POgBBQBlmL9lVoboWWiWippAWvZb",
        blurhash: nil
      },
      name: "Rudyard Kipling",
      image_path: "/uploads/images/26c057fe-e508-48f9-9c1c-f0f1809465ae.jpg"
    })

  %{authors: [robert_louis_stevenson]} =
    Repo.insert!(%Person{
      authors: [
        %Author{
          name: "Robert Louis Stevenson"
        }
      ],
      thumbnails: %Thumbnails{
        extra_small: "/uploads/images/8472ffe9-d717-4319-9023-c983a05cfb4a-xs.webp",
        small: "/uploads/images/8472ffe9-d717-4319-9023-c983a05cfb4a-sm.webp",
        medium: "/uploads/images/8472ffe9-d717-4319-9023-c983a05cfb4a-md.webp",
        large: "/uploads/images/8472ffe9-d717-4319-9023-c983a05cfb4a-lg.webp",
        extra_large: "/uploads/images/8472ffe9-d717-4319-9023-c983a05cfb4a-lg.webp",
        thumbhash: "0AcCBQB5bB9HN0SzdmIUZ4dwnvYX",
        blurhash: "L297eL0000M{-;%M00?bIU4n_3?b"
      },
      name: "Robert Louis Stevenson",
      description:
        "Robert Louis Balfour Stevenson was a Scottish novelist, poet, and travel writer, and a leading representative of English literature. He was greatly admired by many authors, including Jorge Luis Borges, Ernest Hemingway, Rudyard Kipling and Vladimir Nabokov.\n\nMost modernist writers dismissed him, however, because he was popular and did not write within their narrow definition of literature. It is only recently that critics have begun to look beyond Stevenson's popularity and allow him a place in the Western canon.",
      image_path: "/uploads/images/8472ffe9-d717-4319-9023-c983a05cfb4a.jpg"
    })

  %{authors: [frances_hodgson_burnett]} =
    Repo.insert!(%Person{
      authors: [
        %Author{
          name: "Frances Hodgson Burnett"
        }
      ],
      thumbnails: %Thumbnails{
        extra_small: "/uploads/images/74e9d1e3-8db6-4c3b-9bcb-16693687490e-xs.webp",
        small: "/uploads/images/74e9d1e3-8db6-4c3b-9bcb-16693687490e-sm.webp",
        medium: "/uploads/images/74e9d1e3-8db6-4c3b-9bcb-16693687490e-md.webp",
        large: "/uploads/images/74e9d1e3-8db6-4c3b-9bcb-16693687490e-lg.webp",
        extra_large: "/uploads/images/74e9d1e3-8db6-4c3b-9bcb-16693687490e-xl.webp",
        thumbhash: "oqoABQJ3iI+HuHe4eHmXiIhwdPe4",
        blurhash: nil
      },
      name: "Frances Hodgson Burnett",
      description:
        "Frances Eliza Hodgson Burnett was a British-American novelist and playwright. She is best known for the three children's novels Little Lord Fauntleroy (1886), A Little Princess (1905), and The Secret Garden (1911).\nFrances Eliza Hodgson was born in Cheetham, Manchester, England. After her father died in 1853, when Frances was 4 years old, the family fell on straitened circumstances and in 1865 emigrated to the United States, settling in New Market, Tennessee. Frances began her writing career there at age 19 to help earn money for the family, publishing stories in magazines. In 1870, her mother died. In Knoxville, Tennessee, in 1873 she married Swan M. Burnett, who became a medical doctor. Their first son Lionel was born a year later. The Burnetts lived for two years in Paris, where their second son Vivian was born, before returning to the United States to live in Washington, D.C. Burnett then began to write novels, the first of which (That Lass o' Lowrie's), was published to good reviews. Little Lord Fauntleroy was published in 1886 and made her a popular writer of children's fiction, although her romantic adult novels written in the 1890s were also popular. She wrote and helped to produce stage versions of Little Lord Fauntleroy and A Little Princess.\nBeginning in the 1880s, Burnett began to travel to England frequently and in the 1890s bought a home there, where she wrote The Secret Garden. Her elder son, Lionel, died of tuberculosis in 1890, which caused a relapse of the depression she had struggled with for much of her life. She divorced Swan Burnett in 1898, married Stephen Townesend in 1900, and divorced him in 1902. A few years later she settled in Nassau County, New York, where she died in 1924 and is buried in Roslyn Cemetery.\nIn 1936, a memorial sculpture by Bessie Potter Vonnoh was erected in her honor in Central Park's Conservatory Garden. The statue depicts her two famous Secret Garden characters, Mary and Dickon.",
      image_path: "/uploads/images/74e9d1e3-8db6-4c3b-9bcb-16693687490e.jpg"
    })

  %{authors: [alexandre_dumas]} =
    Repo.insert!(%Person{
      authors: [
        %Author{
          name: "Alexandre Dumas"
        }
      ],
      thumbnails: %Thumbnails{
        extra_small: "/uploads/images/49350e87-cfd9-4884-af38-df935a26ab60-xs.webp",
        small: "/uploads/images/49350e87-cfd9-4884-af38-df935a26ab60-sm.webp",
        medium: "/uploads/images/49350e87-cfd9-4884-af38-df935a26ab60-md.webp",
        large: "/uploads/images/49350e87-cfd9-4884-af38-df935a26ab60-lg.webp",
        extra_large: "/uploads/images/49350e87-cfd9-4884-af38-df935a26ab60-xl.webp",
        thumbhash: "CAgCBQCHl4GId4cHZ4UIZoeAhgdo",
        blurhash: "L1AmVc0000.8t1S}000000_2x]?H"
      },
      name: "Alexandre Dumas",
      description:
        "Alexandre Dumas, born Dumas Davy de la Pailleterie; (24 July 1802 – 5 December 1870), also known as Alexandre Dumas, père, was a French writer. His works have been translated into nearly 100 languages, and he is one of the most widely read French authors. Many of his historical novels of high adventure were originally published as serials, including The Count of Monte Cristo, The Three Musketeers, Twenty Years After, and The Vicomte de Bragelonne: Ten Years Later. His novels have been adapted since the early twentieth century for nearly 200 films. Dumas' last novel, The Knight of Sainte-Hermine, unfinished at his death, was completed by a scholar and published in 2005, becoming a bestseller. It was published in English in 2008 as The Last Cavalier",
      image_path: "/uploads/images/49350e87-cfd9-4884-af38-df935a26ab60.jpg"
    })

  %{authors: [emmuska_orczy]} =
    Repo.insert!(%Person{
      authors: [
        %Author{
          name: "Emmuska Orczy"
        }
      ],
      thumbnails: %Thumbnails{
        extra_small: "/uploads/images/6574da90-c914-4ac9-8823-1d8d311d0d36-xs.webp",
        small: "/uploads/images/6574da90-c914-4ac9-8823-1d8d311d0d36-sm.webp",
        medium: "/uploads/images/6574da90-c914-4ac9-8823-1d8d311d0d36-md.webp",
        large: "/uploads/images/6574da90-c914-4ac9-8823-1d8d311d0d36-md.webp",
        extra_large: "/uploads/images/6574da90-c914-4ac9-8823-1d8d311d0d36-md.webp",
        thumbhash: "cEkFFQh4d4WI93i3d42Hd4d6gFf4",
        blurhash: nil
      },
      name: "Emmuska Orczy",
      description:
        "Full name: Emma (\"Emmuska\") Magdolna Rozália Mária Jozefa Borbála Orczy de Orczi was a Hungarian-British novelist, best remembered as the author of THE SCARLET PIMPERNEL (1905). Baroness Orczy's sequels to the novel were less successful. She was also an artist, and her works were exhibited at the Royal Academy, London. Her first venture into fiction was with crime stories. Among her most popular characters was The Old Man in the Corner, who was featured in a series of twelve British movies from 1924, starring Rolf Leslie.\n\nBaroness Emmuska Orczy was born in Tarnaörs, Hungary, as the only daughter of Baron Felix Orczy, a noted composer and conductor, and his wife Emma. Her father was a friend of such composers as Wagner, Liszt, and Gounod. Orczy moved with her parents from Budapest to Brussels and then to London, learning to speak English at the age of fifteen. She was educated in convent schools in Brussels and Paris. In London she studied at the West London School of Art. Orczy married in 1894 Montague Barstow, whom she had met while studying at the Heatherby School of Art. Together they started to produce book and magazine illustrations and published an edition of Hungarian folktales.\n\nOrczy's first detective stories appeared in magazines. As a writer she became famous in 1903 with the stage version of the Scarlet Pimpernel.",
      image_path: "/uploads/images/6574da90-c914-4ac9-8823-1d8d311d0d36.jpg"
    })

  %{narrators: [cliff_stone]} =
    Repo.insert!(%Person{
      narrators: [
        %Narrator{
          name: "Cliff Stone"
        }
      ],
      name: "Cliff Stone",
      description: "A LibriVox reader from Sydney, Australia."
    })

  %{narrators: [mark_nelson]} =
    Repo.insert!(%Person{
      narrators: [
        %Narrator{
          name: "Mark Nelson"
        }
      ],
      name: "Mark Nelson",
      description: "A LibriVox reader"
    })

  %{narrators: [mark_f_smith]} =
    Repo.insert!(%Person{
      narrators: [
        %Narrator{
          name: "Mark F. Smith"
        }
      ],
      name: "Mark F. Smith",
      description: "A LibriVox reader"
    })

  %{narrators: [laurie_anne_walden]} =
    Repo.insert!(%Person{
      narrators: [
        %Narrator{
          name: "Laurie Anne Walden"
        }
      ],
      name: "Laurie Anne Walden",
      description: "A LibriVox reader"
    })

  %{narrators: [david_clarke]} =
    Repo.insert!(%Person{
      narrators: [
        %Narrator{
          name: "David Clarke"
        }
      ],
      name: "David Clarke",
      description: "A LibriVox reader"
    })

  %{narrators: [meredith_hughes]} =
    Repo.insert!(%Person{
      narrators: [
        %Narrator{
          name: "Meredith Hughes"
        }
      ],
      name: "Meredith Hughes",
      description: "A LibriVox reader"
    })

  %{narrators: [karen_savage]} =
    Repo.insert!(%Person{
      narrators: [
        %Narrator{
          name: "Karen Savage"
        }
      ],
      name: "Karen Savage",
      description: "A LibriVox reader"
    })

  %{narrators: [adrian_praetzellis]} =
    Repo.insert!(%Person{
      narrators: [
        %Narrator{
          name: "Adrian Praetzellis"
        }
      ],
      name: "Adrian Praetzellis",
      description: "A LibriVox reader"
    })

  ## Books ##

  the_time_machine =
    Repo.insert!(%Book{
      book_authors: [
        %BookAuthor{
          author_id: h_g_wells.id
        }
      ],
      title: "The Time Machine",
      published: ~D[1895-01-01],
      published_format: :year
    })

  treasure_island =
    Repo.insert!(%Book{
      book_authors: [
        %BookAuthor{
          author_id: robert_louis_stevenson.id
        }
      ],
      title: "Treasure Island",
      published: ~D[1882-01-28],
      published_format: :full
    })

  the_mysterious_island =
    Repo.insert!(%Book{
      book_authors: [
        %BookAuthor{
          author_id: jules_verne.id
        }
      ],
      title: "The Mysterious Island",
      published: ~D[1874-01-01],
      published_format: :year
    })

  a_princess_of_mars =
    Repo.insert!(%Book{
      book_authors: [
        %BookAuthor{
          author_id: edgar_rice_burroughs.id
        }
      ],
      title: "A Princess of Mars",
      published: ~D[1912-02-07],
      published_format: :full
    })

  the_scarlet_pimpernel =
    Repo.insert!(%Book{
      book_authors: [
        %BookAuthor{
          author_id: emmuska_orczy.id
        }
      ],
      title: "The Scarlet Pimpernel",
      published: ~D[1905-01-01],
      published_format: :year
    })

  the_count_of_monte_cristo =
    Repo.insert!(%Book{
      book_authors: [
        %BookAuthor{
          author_id: alexandre_dumas.id
        }
      ],
      title: "The Count of Monte Cristo",
      published: ~D[1844-08-28],
      published_format: :full
    })

  the_jungle_book =
    Repo.insert!(%Book{
      book_authors: [
        %BookAuthor{
          author_id: rudyard_kipling.id
        }
      ],
      title: "The Jungle Book",
      published: ~D[1894-01-01],
      published_format: :year
    })

  anne_of_green_gables =
    Repo.insert!(%Book{
      book_authors: [
        %BookAuthor{
          author_id: l_m_montgomery.id
        }
      ],
      title: "Anne of Green Gables",
      published: ~D[1908-01-01],
      published_format: :full
    })

  the_secret_garden =
    Repo.insert!(%Book{
      book_authors: [
        %BookAuthor{
          author_id: frances_hodgson_burnett.id
        }
      ],
      title: "The Secret Garden",
      published: ~D[1911-08-01],
      published_format: :year_month
    })

  the_hound_of_the_baskervilles =
    Repo.insert!(%Book{
      book_authors: [
        %BookAuthor{
          author_id: arthur_conan_doyle.id
        }
      ],
      title: "The Hound of the Baskervilles",
      published: ~D[1902-03-25],
      published_format: :full
    })

  ## Media ##

  Repo.insert!(%Media{
    book_id: the_time_machine.id,
    media_narrators: [
      %MediaNarrator{
        narrator_id: mark_f_smith.id
      }
    ],
    thumbnails: %Thumbnails{
      extra_small: "/uploads/images/57e6fe29-289a-429e-862c-57b6c5d8bc67-xs.webp",
      small: "/uploads/images/57e6fe29-289a-429e-862c-57b6c5d8bc67-sm.webp",
      medium: "/uploads/images/57e6fe29-289a-429e-862c-57b6c5d8bc67-md.webp",
      large: "/uploads/images/57e6fe29-289a-429e-862c-57b6c5d8bc67-lg.webp",
      extra_large: "/uploads/images/57e6fe29-289a-429e-862c-57b6c5d8bc67-lg.webp",
      thumbhash: "qRgKDQCniH6FJ4gGeGNXN6d/Uvk3",
      blurhash: "L6P?aD8_-;_M_Mt7t7WW0ft6ofkB"
    },
    status: :ready,
    source_path: "/app/uploads/source_media/8ab5c5d5-be2d-4b7d-8021-c4b170f8ad9a",
    mpd_path: "/uploads/media/e01fadd2-49ed-413e-8839-00dd2cf7137c.mpd",
    hls_path: "/uploads/media/e01fadd2-49ed-413e-8839-00dd2cf7137c.m3u8",
    mp4_path: "/uploads/media/e01fadd2-49ed-413e-8839-00dd2cf7137c.mp4",
    duration: Decimal.new("13153.175011"),
    published: ~D[2011-07-09],
    published_format: :full,
    image_path: "/uploads/images/57e6fe29-289a-429e-862c-57b6c5d8bc67.jpg",
    description:
      "\"I've had a most amazing time....\"\n\nSo begins the Time Traveller's astonishing firsthand account of his journey 800,000 years beyond his own era—and the story that launched H.G. Wells's successful career and earned him his reputation as the father of science fiction. With a speculative leap that still fires the imagination, Wells sends his brave explorer to face a future burdened with our greatest hopes...and our darkest fears. A pull of the Time Machine's lever propels him to the age of a slowly dying Earth. There he discovers two bizarre races—the ethereal Eloi and the subterranean Morlocks—who not only symbolize the duality of human nature, but offer a terrifying portrait of the men of tomorrow as well. Published in 1895, this masterpiece of invention captivated readers on the threshold of a new century. Thanks to Wells's expert storytelling and provocative insight,  **The Time Machine**  will continue to enthrall readers for generations to come.",
    publisher: "LibriVox"
  })

  Repo.insert!(%Media{
    book_id: the_scarlet_pimpernel.id,
    media_narrators: [
      %MediaNarrator{
        narrator_id: karen_savage.id
      }
    ],
    thumbnails: %Thumbnails{
      extra_small: "/uploads/images/80371d2d-2923-4e19-8d5b-0561b5bbdc7e-xs.webp",
      small: "/uploads/images/80371d2d-2923-4e19-8d5b-0561b5bbdc7e-sm.webp",
      medium: "/uploads/images/80371d2d-2923-4e19-8d5b-0561b5bbdc7e-md.webp",
      large: "/uploads/images/80371d2d-2923-4e19-8d5b-0561b5bbdc7e-lg.webp",
      extra_large: "/uploads/images/80371d2d-2923-4e19-8d5b-0561b5bbdc7e-lg.webp",
      thumbhash: "o0gGDQIMV4l3t3iId4aIh/GHB32H",
      blurhash: "LSIzPHuhaenO^+%foLn%OFxGWBR*"
    },
    status: :ready,
    source_path: "/app/uploads/source_media/74a8b0f8-cf8c-4aa3-9949-7917655a77ce",
    mpd_path: "/uploads/media/480eb4cf-29b4-485f-8cad-6a88b32dd382.mpd",
    hls_path: "/uploads/media/480eb4cf-29b4-485f-8cad-6a88b32dd382.m3u8",
    mp4_path: "/uploads/media/480eb4cf-29b4-485f-8cad-6a88b32dd382.mp4",
    duration: Decimal.new("27554.052063"),
    published: ~D[2007-03-16],
    published_format: :full,
    image_path: "/uploads/images/80371d2d-2923-4e19-8d5b-0561b5bbdc7e.jpg",
    description:
      "Armed with only his wits and his cunning, one man recklessly defies the French revolutionaries and rescues scores of innocent men, women, and children from the deadly guillotine. His friends and foes know him only as the Scarlet Pimpernel. But the ruthless French agent Chauvelin is sworn to discover his identity and to hunt him down.",
    publisher: "LibriVox"
  })

  Repo.insert!(%Media{
    book_id: treasure_island.id,
    media_narrators: [
      %MediaNarrator{
        narrator_id: adrian_praetzellis.id
      }
    ],
    thumbnails: %Thumbnails{
      extra_small: "/uploads/images/fb173bc1-446a-4dbb-8fb2-332ed54ca29d-xs.webp",
      small: "/uploads/images/fb173bc1-446a-4dbb-8fb2-332ed54ca29d-sm.webp",
      medium: "/uploads/images/fb173bc1-446a-4dbb-8fb2-332ed54ca29d-md.webp",
      large: "/uploads/images/fb173bc1-446a-4dbb-8fb2-332ed54ca29d-lg.webp",
      extra_large: "/uploads/images/fb173bc1-446a-4dbb-8fb2-332ed54ca29d-lg.webp",
      thumbhash: "YaYFNQR3mIB4t4h4d4eIZ2eAewa4",
      blurhash: "LPEyJfkC7QNbXAs:juNIK+f6wGoL"
    },
    status: :ready,
    source_path: "/app/uploads/source_media/09bb82ef-7e65-4fa1-8202-96175df67915",
    mpd_path: "/uploads/media/d52151bb-d906-4e30-bbae-a7e7eaac2593.mpd",
    hls_path: "/uploads/media/d52151bb-d906-4e30-bbae-a7e7eaac2593.m3u8",
    mp4_path: "/uploads/media/d52151bb-d906-4e30-bbae-a7e7eaac2593.mp4",
    duration: Decimal.new("26659.155011"),
    published: ~D[2007-12-14],
    published_format: :full,
    image_path: "/uploads/images/fb173bc1-446a-4dbb-8fb2-332ed54ca29d.jpg",
    description:
      "\"For sheer storytelling delight and pure adventure,  _Treasure Island_  has never been surpassed. From the moment young Jim Hawkins first encounters the sinister Blind Pew at the Admiral Benbow Inn until the climactic battle for treasure on a tropic isle, the novel creates scenes and characters that have fired the imaginations of generations of readers. Written by a superb prose stylist, a master of both action and atmosphere, the story centers upon the conflict between good and evil - but in this case a particularly engaging form of evil. It is the villainy of that most ambiguous rogue Long John Silver that sets the tempo of this tale of treachery, greed, and daring. Designed to forever kindle a dream of high romance and distant horizons,  _Treasure Island_  is, in the words of G. K. Chesterton, 'the realization of an ideal, that which is promised in its provocative and beckoning map; a vision not only of white skeletons but also green palm trees and sapphire seas.' G. S. Fraser terms it 'an utterly original book' and goes on to write: 'There will always be a place for stories like  _Treasure Island_  that can keep boys and old men happy.'",
    publisher: "LibriVox"
  })

  Repo.insert!(%Media{
    book_id: the_mysterious_island.id,
    media_narrators: [
      %MediaNarrator{
        narrator_id: mark_f_smith.id
      }
    ],
    thumbnails: %Thumbnails{
      extra_small: "/uploads/images/7e1e3e4d-95c8-49d8-90d6-16ad3d8ea6fc-xs.webp",
      small: "/uploads/images/7e1e3e4d-95c8-49d8-90d6-16ad3d8ea6fc-sm.webp",
      medium: "/uploads/images/7e1e3e4d-95c8-49d8-90d6-16ad3d8ea6fc-md.webp",
      large: "/uploads/images/7e1e3e4d-95c8-49d8-90d6-16ad3d8ea6fc-lg.webp",
      extra_large: "/uploads/images/7e1e3e4d-95c8-49d8-90d6-16ad3d8ea6fc-lg.webp",
      thumbhash: "YAgSBQCHl4mH93eod4qYd5yj32/4",
      blurhash: "LHEyYxD%-;M{M{oeRjaz~qWBayj["
    },
    status: :ready,
    source_path: "/app/uploads/source_media/eca00c0f-5078-4f77-b3cc-dc1ab1113531",
    mpd_path: "/uploads/media/1e63b924-dcb0-4f9d-869b-9924cc6c4185.mpd",
    hls_path: "/uploads/media/1e63b924-dcb0-4f9d-869b-9924cc6c4185.m3u8",
    mp4_path: "/uploads/media/1e63b924-dcb0-4f9d-869b-9924cc6c4185.mp4",
    duration: Decimal.new("79105.600385"),
    published: ~D[2007-05-10],
    published_format: :full,
    image_path: "/uploads/images/7e1e3e4d-95c8-49d8-90d6-16ad3d8ea6fc.jpg",
    description:
      "After hijacking a balloon from a Confederate camp, a band of five northern prisoners escapes the American Civil War. Seven thousand miles later, they drop from the clouds onto an uncharted volcanic island in the Pacific. Through teamwork, scientific knowledge, engineering, and perseverance, they endeavour to build a colony from scratch. But this island of abundant resources has its secrets. The castaways discover they are not alone. A shadowy, yet familiar, agent of their unfathomable fate is watching.\n\nWhat unfolds in Jules Verne's imaginative marvel is both an enthralling mystery and the ultimate in survivalist adventures.",
    publisher: "LibriVox"
  })

  Repo.insert!(%Media{
    book_id: a_princess_of_mars.id,
    media_narrators: [
      %MediaNarrator{
        narrator_id: mark_nelson.id
      }
    ],
    thumbnails: %Thumbnails{
      extra_small: "/uploads/images/7ec1ca7c-c286-4d4c-8c31-9f56cd7407c5-xs.webp",
      small: "/uploads/images/7ec1ca7c-c286-4d4c-8c31-9f56cd7407c5-sm.webp",
      medium: "/uploads/images/7ec1ca7c-c286-4d4c-8c31-9f56cd7407c5-md.webp",
      large: "/uploads/images/7ec1ca7c-c286-4d4c-8c31-9f56cd7407c5-lg.webp",
      extra_large: "/uploads/images/7ec1ca7c-c286-4d4c-8c31-9f56cd7407c5-lg.webp",
      thumbhash: "UfgFBQBnqIt4p5j2Z3yHeFmAYfu2",
      blurhash: "LBD0S*_L01IUIUxt%MIV02Rj_2oz"
    },
    status: :ready,
    source_path: "/app/uploads/source_media/ef4d8f9f-598e-4c7c-a4b8-81cae7fca005",
    mpd_path: "/uploads/media/5b5db89a-674d-4044-b619-c01756062f6d.mpd",
    hls_path: "/uploads/media/5b5db89a-674d-4044-b619-c01756062f6d.m3u8",
    mp4_path: "/uploads/media/5b5db89a-674d-4044-b619-c01756062f6d.mp4",
    duration: Decimal.new("26311.936000"),
    published: ~D[2008-10-10],
    published_format: :full,
    image_path: "/uploads/images/7ec1ca7c-c286-4d4c-8c31-9f56cd7407c5.jpg",
    description:
      "A Princess of Mars is the first of eleven thrilling novels that comprise Edgar Rice Burroughs' most exciting saga, known as The Martian Series. It's the beginning of an incredible odyssey in which John Carter, a gentleman from Virginia and a Civil War veteran, unexpectedly finds himself on to the red planet, scene of continuing combat among rival tribes. Captured by a band of six-limbed, green-skinned savage giants called Tharks, Carter soon is accorded all the honor of a chieftain after it's discovered that his muscles, accustomed to Earth's greater gravity, now give him a decided advantage in strength. And when his captors take as prisoner Dejah Thoris, the lovely human-looking princess of the city of Helium, Carter must call upon every ounce of strength, courage, and ingenuity to rescue her-before Dejah becomes the slave of the depraved Thark leader, Tal Hajus!",
    publisher: "LibriVox"
  })

  Repo.insert!(%Media{
    book_id: the_jungle_book.id,
    media_narrators: [
      %MediaNarrator{
        narrator_id: meredith_hughes.id
      }
    ],
    thumbnails: %Thumbnails{
      extra_small: "/uploads/images/58a889ba-73bb-41ce-a30b-427470b7f2f3-xs.webp",
      small: "/uploads/images/58a889ba-73bb-41ce-a30b-427470b7f2f3-sm.webp",
      medium: "/uploads/images/58a889ba-73bb-41ce-a30b-427470b7f2f3-md.webp",
      large: "/uploads/images/58a889ba-73bb-41ce-a30b-427470b7f2f3-lg.webp",
      extra_large: "/uploads/images/58a889ba-73bb-41ce-a30b-427470b7f2f3-lg.webp",
      thumbhash: "5MgFBQDNuH+X6GfXd3mJd71/LhIJ",
      blurhash: "LAHV|R_K%e.6DloyRjV[MztQt6V["
    },
    status: :ready,
    source_path: "/app/uploads/source_media/bc68c3d5-936b-41be-8b15-13936d5c679c",
    mpd_path: "/uploads/media/dac8816f-fb6a-4989-905a-0e6d9780a4c0.mpd",
    hls_path: "/uploads/media/dac8816f-fb6a-4989-905a-0e6d9780a4c0.m3u8",
    mp4_path: "/uploads/media/dac8816f-fb6a-4989-905a-0e6d9780a4c0.mp4",
    duration: Decimal.new("18024.201723"),
    published: ~D[2008-08-13],
    published_format: :full,
    image_path: "/uploads/images/58a889ba-73bb-41ce-a30b-427470b7f2f3.jpg",
    description:
      "'There is no harm in a man's cub.'\n\nBest known for the 'Mowgli' stories, Rudyard Kipling's The Jungle Book expertly interweaves myth, morals, adventure and powerful story-telling. Set in Central India, Mowgli is raised by a pack of wolves. Along the way he encounters memorable characters such as the foreboding tiger Shere Kahn, Bagheera the panther and Baloo the bear. Including other stories such as that of Rikki-Tikki-Tavi, a heroic mongoose and Toomai, a young elephant handler, Kipling's fables remain as popular today as they ever were.",
    publisher: "LibriVox"
  })

  Repo.insert!(%Media{
    book_id: anne_of_green_gables.id,
    media_narrators: [
      %MediaNarrator{
        narrator_id: karen_savage.id
      }
    ],
    thumbnails: %Thumbnails{
      extra_small: "/uploads/images/07267014-e2d7-44d3-a206-d91a9dfa27e3-xs.webp",
      small: "/uploads/images/07267014-e2d7-44d3-a206-d91a9dfa27e3-sm.webp",
      medium: "/uploads/images/07267014-e2d7-44d3-a206-d91a9dfa27e3-md.webp",
      large: "/uploads/images/07267014-e2d7-44d3-a206-d91a9dfa27e3-lg.webp",
      extra_large: "/uploads/images/07267014-e2d7-44d3-a206-d91a9dfa27e3-lg.webp",
      thumbhash: "nFkGDQJ4d494h3eYiHeHeHiPiPeI",
      blurhash: "LLG7*hjt}qa|$Mj@S2azW-j@%1oL"
    },
    status: :ready,
    source_path: "/app/uploads/source_media/6df0fd4d-6612-479f-a1f0-43b1bf77c934",
    mpd_path: "/uploads/media/6cdce5ec-a4ad-4b12-a8b8-9c486070d080.mpd",
    hls_path: "/uploads/media/6cdce5ec-a4ad-4b12-a8b8-9c486070d080.m3u8",
    mp4_path: "/uploads/media/6cdce5ec-a4ad-4b12-a8b8-9c486070d080.mp4",
    duration: Decimal.new("31075.218866"),
    published: ~D[2007-06-12],
    published_format: :full,
    image_path: "/uploads/images/07267014-e2d7-44d3-a206-d91a9dfa27e3.jpg",
    description:
      "This heartwarming story has beckoned generations of readers into the special world of Green Gables, an old-fashioned farm outside a town called Avonlea. Anne Shirley, an eleven-year-old orphan, has arrived in this verdant corner of Prince Edward Island only to discover that the Cuthberts—elderly Matthew and his stern sister, Marilla—want to adopt a boy, not a feisty redheaded girl. But before they can send her back, Anne—who simply must have more scope for her imagination and a real home—wins them over completely. A much-loved classic that explores all the vulnerability, expectations, and dreams of a child growing up,  _Anne of Green Gables_  is also a wonderful portrait of a time, a place, a family… and, most of all, love. ",
    publisher: "LibriVox"
  })

  Repo.insert!(%Media{
    book_id: the_hound_of_the_baskervilles.id,
    media_narrators: [
      %MediaNarrator{
        narrator_id: laurie_anne_walden.id
      }
    ],
    thumbnails: %Thumbnails{
      extra_small: "/uploads/images/fddc237f-a9ac-48f9-93c0-0d3e771d4f07-xs.webp",
      small: "/uploads/images/fddc237f-a9ac-48f9-93c0-0d3e771d4f07-sm.webp",
      medium: "/uploads/images/fddc237f-a9ac-48f9-93c0-0d3e771d4f07-md.webp",
      large: "/uploads/images/fddc237f-a9ac-48f9-93c0-0d3e771d4f07-lg.webp",
      extra_large: "/uploads/images/fddc237f-a9ac-48f9-93c0-0d3e771d4f07-lg.webp",
      thumbhash: "FOoGBQK6pXCWRnd4iImYl4tgUvXZ",
      blurhash: "L4JEhvM|00?Z8}W:-.RQ|]az70xZ"
    },
    status: :ready,
    source_path: "/app/uploads/source_media/431f0e0d-e6b4-4fac-b65a-e9c46ca8f35a",
    mpd_path: "/uploads/media/e8f6e520-fec9-428c-a7b0-97780b6b7639.mpd",
    hls_path: "/uploads/media/e8f6e520-fec9-428c-a7b0-97780b6b7639.m3u8",
    mp4_path: "/uploads/media/e8f6e520-fec9-428c-a7b0-97780b6b7639.mp4",
    duration: Decimal.new("21185.920000"),
    published: ~D[2007-03-29],
    published_format: :full,
    image_path: "/uploads/images/fddc237f-a9ac-48f9-93c0-0d3e771d4f07.jpg",
    description:
      "In this, one of the most famous of Doyle's mysteries, the tale of an ancient curse and a savage ghostly hound comes frighteningly to life. The gray towers of Baskerville Hall and the wild open country of Dartmoor will haunt the reader as Holmes and Watson seek to unravel the many secrets of the misty English bogs.",
    publisher: "LibriVox"
  })

  Repo.insert!(%Media{
    book_id: the_secret_garden.id,
    media_narrators: [
      %MediaNarrator{
        narrator_id: karen_savage.id
      }
    ],
    thumbnails: %Thumbnails{
      extra_small: "/uploads/images/080bfcd6-1f58-4d10-ae09-d94b5a365cf6-xs.webp",
      small: "/uploads/images/080bfcd6-1f58-4d10-ae09-d94b5a365cf6-sm.webp",
      medium: "/uploads/images/080bfcd6-1f58-4d10-ae09-d94b5a365cf6-md.webp",
      large: "/uploads/images/080bfcd6-1f58-4d10-ae09-d94b5a365cf6-lg.webp",
      extra_large: "/uploads/images/080bfcd6-1f58-4d10-ae09-d94b5a365cf6-lg.webp",
      thumbhash: "2wgGDQKFaIWHB2hXiHZnJ4SAZwXo",
      blurhash: "L8GbO{~W0K00cBM}^%xZ0z9a^7^+"
    },
    status: :ready,
    source_path: "/app/uploads/source_media/9a414550-7669-4124-b7c8-0c80a5b1ade4",
    mpd_path: "/uploads/media/871fdad3-1e3e-444c-9615-7317f50e6d31.mpd",
    hls_path: "/uploads/media/871fdad3-1e3e-444c-9615-7317f50e6d31.m3u8",
    mp4_path: "/uploads/media/871fdad3-1e3e-444c-9615-7317f50e6d31.mp4",
    duration: Decimal.new("25061.343492"),
    published: ~D[2009-10-19],
    published_format: :full,
    image_path: "/uploads/images/080bfcd6-1f58-4d10-ae09-d94b5a365cf6.jpg",
    description:
      "In a house full of sadness and secrets, can young, orphaned Mary find happiness?\n\nMary Lennox, a spoiled, ill-tempered, and unhealthy child, comes to live with her reclusive uncle in Misselthwaite Manor on England's Yorkshire moors after the death of her parents. There she meets a hearty housekeeper and her spirited brother, a dour gardener, a cheerful robin, and her wilful, hysterical, and sickly cousin, Master Colin, whose wails she hears echoing through the house at night.\n\nWith the help of the robin, Mary finds the door to a secret garden, neglected and hidden for years. When she decides to restore the garden in secret, the story becomes a charming journey into the places of the heart, where faith restores health, flowers refresh the spirit, and the magic of the garden, coming to life anew, brings health to Colin and happiness to Mary.",
    publisher: "LibriVox"
  })

  Repo.insert!(%Media{
    book_id: the_count_of_monte_cristo.id,
    media_narrators: [
      %MediaNarrator{
        narrator_id: david_clarke.id
      }
    ],
    thumbnails: %Thumbnails{
      extra_small: "/uploads/images/130b30a8-ae83-4aef-b252-7f0cd869c0c5-xs.webp",
      small: "/uploads/images/130b30a8-ae83-4aef-b252-7f0cd869c0c5-sm.webp",
      medium: "/uploads/images/130b30a8-ae83-4aef-b252-7f0cd869c0c5-md.webp",
      large: "/uploads/images/130b30a8-ae83-4aef-b252-7f0cd869c0c5-lg.webp",
      extra_large: "/uploads/images/130b30a8-ae83-4aef-b252-7f0cd869c0c5-lg.webp",
      thumbhash: "zPcBBQCNFBS1/a43YrtZpudweA2G",
      blurhash: "L18qEF}-00?]?wt8In0200-p_2E2"
    },
    status: :ready,
    source_path: "/app/uploads/source_media/c2e1f1f2-983b-4e3c-8057-b1584cb44344",
    mpd_path: "/uploads/media/690a5f6d-4592-4611-8f72-002aac108b0b.mpd",
    hls_path: "/uploads/media/690a5f6d-4592-4611-8f72-002aac108b0b.m3u8",
    mp4_path: "/uploads/media/690a5f6d-4592-4611-8f72-002aac108b0b.mp4",
    duration: Decimal.new("195434.811791"),
    published: ~D[2013-08-09],
    published_format: :full,
    image_path: "/uploads/images/130b30a8-ae83-4aef-b252-7f0cd869c0c5.jpg",
    description:
      " **The epic tale of wrongful imprisonment, adventure and revenge, in its definitive translation** \n\nThrown in prison for a crime he has not committed, Edmond Dantès is confined to the grim fortress of If. There he learns of a great hoard of treasure hidden on the Isle of Monte Cristo and he becomes determined not only to escape, but also to use the treasure to plot the destruction of the three men responsible for his incarceration. Dumas' epic tale of suffering and retribution, inspired by a real-life case of wrongful imprisonment, was a huge popular success when it was first serialized in the 1840s.",
    publisher: "LibriVox"
  })

  Repo.insert!(%Media{
    book_id: the_time_machine.id,
    media_narrators: [
      %MediaNarrator{
        narrator_id: cliff_stone.id
      }
    ],
    thumbnails: %Thumbnails{
      extra_small: "/uploads/images/e3af413b-3685-4fd2-b0b1-30eb94bd0ee4-xs.webp",
      small: "/uploads/images/e3af413b-3685-4fd2-b0b1-30eb94bd0ee4-sm.webp",
      medium: "/uploads/images/e3af413b-3685-4fd2-b0b1-30eb94bd0ee4-md.webp",
      large: "/uploads/images/e3af413b-3685-4fd2-b0b1-30eb94bd0ee4-lg.webp",
      extra_large: "/uploads/images/e3af413b-3685-4fd2-b0b1-30eb94bd0ee4-lg.webp",
      thumbhash: "SxgCBQBpc2B4ibdXZ3h2aGpwjweX",
      blurhash: "L1Am6o%100Ip^*x[9Zax00D*-UWB"
    },
    status: :ready,
    source_path: "/app/uploads/source_media/92b8ff82-4904-450c-ac44-f7c6f3787db7",
    mpd_path: "/uploads/media/502f2012-70dc-4e61-b245-4cd0aa1db236.mpd",
    hls_path: "/uploads/media/502f2012-70dc-4e61-b245-4cd0aa1db236.m3u8",
    mp4_path: "/uploads/media/502f2012-70dc-4e61-b245-4cd0aa1db236.mp4",
    duration: Decimal.new("12411.042540"),
    published: ~D[2021-05-12],
    published_format: :full,
    image_path: "/uploads/images/e3af413b-3685-4fd2-b0b1-30eb94bd0ee4.jpg",
    description:
      "\"I've had a most amazing time....\"\n\nSo begins the Time Traveller's astonishing firsthand account of his journey 800,000 years beyond his own era—and the story that launched H.G. Wells's successful career and earned him his reputation as the father of science fiction. With a speculative leap that still fires the imagination, Wells sends his brave explorer to face a future burdened with our greatest hopes...and our darkest fears. A pull of the Time Machine's lever propels him to the age of a slowly dying Earth. There he discovers two bizarre races—the ethereal Eloi and the subterranean Morlocks—who not only symbolize the duality of human nature, but offer a terrifying portrait of the men of tomorrow as well. Published in 1895, this masterpiece of invention captivated readers on the threshold of a new century. Thanks to Wells's expert storytelling and provocative insight,  **The Time Machine**  will continue to enthrall readers for generations to come.",
    publisher: "LibriVox"
  })
end)
