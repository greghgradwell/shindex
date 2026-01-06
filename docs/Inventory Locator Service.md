## Goal

To track every single item that I own, allowing me to locate them quickly, and offer them for rent/sale/borrow at any time, if desired.

## Motivation

As an engineer, I have a LOT of items in my workshop. I have them mostly organized into labeled bins, but even with this it sometimes takes me a few minutes to find the right bin of a particular item. Plus, I have no way of knowing if I have a particular item in stock, or how many. I have often bought items I didn’t need, thinking I didn’t have them, or found myself without important items at critical times because I thought they were in stock. Also, there are some items I own that I would gladly sell or lend, but I don’t want to take the time to list each of them individually on a marketplace. That would be time consuming and expensive. Plus, there isn’t a good marketplace for lending items.

## Method

I want to utilize an inventory system similar to Amazon warehouses, where an item is simply placed in any available location. I should have bins so that all identical items can be placed in a similar location, but some items will not be able to fit in a bin, so that also needs to be considered. I have complete control of my workshop, so I can label shelves and bins however I need to. Some items will not fit on shelves, and therefore will need to be placed on the floor. However, I can still have ways of indicating their location.

I need a way to quickly add an item to my inventory. Each record should include a picture of the item, either from the website it was purchased from, or from my own camera. There needs to be a mechanism that prevents duplicate instances from being created.

I need to be able to search my inventory quickly, either from my phone or computer. This suggests that the inventory needs to be hosted on a webpage. However, for the initial prototype, this webpage does not need to be on the open web, but could be hosted on a machine on my local network. This would simplify security requirements at the beginning.

Other people should be able to search my inventory. I should be able to mark items as public or private. Eventually I should be able to have different levels of visibility. For example, I will let my close friends view my entire inventory, whereas I might have a subset of items that are visible to the general public. I should be able to invite people to my inventory site with a custom link that grants them the correct access, similar to how Google Docs does.

Every item should have a sale price and a rental price. The rental terms might vary between items, i.e., “$10 per hour”, “$50 per week”. I will not be taking payments through the website yet, so we don’t have to handle that. I should be able to change the rental price for different access levels. For example, my close friends will be able to borrow things for free (or any price that I set), whereas the general public will have a pay a different price.

## Implementation

Elixir is my favorite programming language. However, it has been a while since I used it. I have also never written Elixir code using an AI coding tool. This project should be a way for me to get reintroduced to Elixir. Given that the inventory will be web-hosted, I think Elixir is a good language choice.

I am open to the method for storing inventory entries. I’m assuming it will be some kind of database. If so, I believe that Elixir-native DETS would be a possibility. However, it might be a poor choice given that I intend my inventory to be eventually hosted on the open web, and searchable by multiple users simultaneously. Thus, SQL or something like it might be a better option, although I am unfamiliar with it (and all databases, for the most part).

We can utilize AI tools for adding to the inventory or searching the inventory, but they must be as deterministic as possible. For example, searching the inventory with a fuzzy search will be fast. If I still can’t find the item I’m looking for, then perhaps using an AI Agent would make sense, as it can search more deeply and use its own reasoning to provide additional results. Likewise, when I’m trying to add an item to the inventory, it probably makes sense to have an AI search through the inventory and suggest existing items that might be a duplicate. In both cases, the human is in the loop. We should never have AI making unsupervised modifications to the database.

## What is Success?

For this project to be successful, the following must be achieved:

1. I need a way to define all the locations that items can be stored. This needs to be very flexible, as I don’t have standardized shelving. Since we’re starting with a blank canvas, I should also be able to define locations as I place items.  
2. A mechanism to quickly add items to the inventory, either from a computer (without a camera), or with a phone (with a camera). This mechanism must guard against duplicates.  
3. A mechanism to quickly search the inventory. I should always be able to find an item, even if I don’t know the exact name of it.  
4. Once the inventory site is open to the web, the inventory should be viewable by anyone, according to their access level. Someone should be able to request to buy or rent the item directly from the website.