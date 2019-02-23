//
//  TableViewController.swift
//  InfiniteScrollViewDemoSwift
//
//  Created by pronebird on 5/3/15.
//  Copyright (c) 2015 pronebird. All rights reserved.
//

import UIKit
import SafariServices

private let useAutosizingCells = true

class TableViewController: UITableViewController {
    
    fileprivate var currentPage = 0
    fileprivate var numPages = 0
    fileprivate var stories = [HackerNewsStory]()
    
    fileprivate var infiniteScroll: InfiniteScroll<UITableView>?
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        if useAutosizingCells && tableView.responds(to: #selector(getter: UIView.layoutMargins)) {
            tableView.estimatedRowHeight = 88
            tableView.rowHeight = UITableViewAutomaticDimension
        }
        
        let infiniteScroll = InfiniteScroll(scrollView: self.tableView, scrollDirection: .vertical)
        infiniteScroll.didBeginUpdating = { [weak self] (tableView, finish) in
            print("didBeginUpdating")
            
            self?.performFetch {
                DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(5), execute: {                    
                    finish()
                })
            }
        }
        
        infiniteScroll.didFinishUpdating = { (tableView) in
            print("didFinishUpdating")
        }
        
        infiniteScroll.shouldBeginUpdating = { () -> Bool in
            print("shouldBeginUpdating")
            return true
        }
        
        // Set custom indicator
        infiniteScroll.indicatorView = CustomInfiniteIndicator(frame: CGRect(x: 0, y: 0, width: 24, height: 24))
        
        // Set custom indicator margin
        infiniteScroll.indicatorMargins = UIEdgeInsets(top: 40, left: 0, bottom: 40, right: 0)
        
        // Set custom trigger offset
        infiniteScroll.triggerOffset = 500
        
        // Uncomment this to provide conditionally prevent the infinite scroll from triggering
        /*
        tableView.setShouldShowInfiniteScrollHandler { [weak self] (tableView) -> Bool in
            // Only show up to 5 pages then prevent the infinite scroll
            return (self?.currentPage < 5);
        }
        */
        
        // load initial data
        infiniteScroll.begin(forceScroll: true)
        
        self.infiniteScroll = infiniteScroll
    }
    
    fileprivate func performFetch(_ completionHandler: (() -> Void)?) {
        fetchData { (result) in
            defer { completionHandler?() }
            
            switch result {
            case .ok(let response):
                // create new index paths
                let storyCount = self.stories.count
                let (start, end) = (storyCount, response.hits.count + storyCount)
                let indexPaths = (start..<end).map { return IndexPath(row: $0, section: 0) }
                
                // update data source
                self.stories.append(contentsOf: response.hits)
                self.numPages = response.nbPages
                self.currentPage += 1
                
                // update table view
                self.tableView.beginUpdates()
                self.tableView.insertRows(at: indexPaths, with: .automatic)
                self.tableView.endUpdates()
                
            case .error(let error):
                self.showAlertWithError(error)
            }
            
        }
    }
    
    fileprivate func showAlertWithError(_ error: Error) {
        let alert = UIAlertController(title: NSLocalizedString("tableView.errorAlert.title", comment: ""),
                                      message: error.localizedDescription,
                                      preferredStyle: .alert)
        
        alert.addAction(UIAlertAction(title: NSLocalizedString("tableView.errorAlert.dismiss", comment: ""),
                                      style: .cancel,
                                      handler: nil))
        
        alert.addAction(UIAlertAction(title: NSLocalizedString("tableView.errorAlert.retry", comment: ""),
                                      style: .default,
                                      handler: { _ in self.performFetch(nil) }))
        
        present(alert, animated: true, completion: nil)
    }

}

// MARK: - Actions

extension TableViewController {
    
    @IBAction func handleRefresh() {
        infiniteScroll?.begin(forceScroll: true)
    }
    
}

// MARK: - UITableViewDelegate

extension TableViewController {
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let story = stories[indexPath.row]
        let url = story.url ?? story.postUrl
        
        if #available(iOS 9.0, *) {
            let safariController = SFSafariViewController(url: url)
            safariController.delegate = self
            
            let safariNavigationController = UINavigationController(rootViewController: safariController)
            safariNavigationController.setNavigationBarHidden(true, animated: false)
            
            present(safariNavigationController, animated: true)
        } else {
            UIApplication.shared.openURL(url)
        }
        
        tableView.deselectRow(at: indexPath, animated: true)
    }
    
}

// MARK: - UITableViewDataSource

extension TableViewController {
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return stories.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let story = stories[indexPath.row]
        
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        cell.textLabel?.text = story.title
        cell.detailTextLabel?.text = story.author
        
        if useAutosizingCells && tableView.responds(to: #selector(getter: UIView.layoutMargins)) {
            cell.textLabel?.numberOfLines = 0
            cell.detailTextLabel?.numberOfLines = 0
        }
        
        return cell
    }
    
}

// MARK: - SFSafariViewControllerDelegate

@available(iOS 9.0, *)
extension TableViewController: SFSafariViewControllerDelegate {
    
    func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
        controller.dismiss(animated: true)
    }
    
}

// MARK: - API

extension TableViewController {
    typealias FetchResult = Result<HackerNewsResponse, FetchError>
   
    fileprivate func makeRequest(numHits: Int, page: Int) -> URLRequest {
        let url = URL(string: "https://hn.algolia.com/api/v1/search_by_date?tags=story&hitsPerPage=\(numHits)&page=\(page)")!
        return URLRequest(url: url)
    }

    fileprivate func fetchData(handler: @escaping ((FetchResult) -> Void)) {
        let hits = Int(tableView.bounds.height) / 44
        let request = makeRequest(numHits: hits, page: currentPage)
        
        let task = URLSession.shared.dataTask(with: request, completionHandler: {
            (data, _, networkError) -> Void in
            DispatchQueue.main.async {
                handler(handleFetchResponse(data: data, networkError: networkError))
            }
        })
        
        // I run task.resume() with delay because my network is too fast
        let delay = (stories.count == 0 ? 0 : 5)

        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(delay), execute: {
            task.resume()
        })
    }
    
}
